-- Automatically moves requests to appropriate queues based on transition 
-- from Checked out to Customer to Request Finished, if the two requests 
-- have the same (unique) lender.

--Author: Michael McGlinchey, Bowdoin College, 2015



function Init()
	LogDebug("Initializing Unique Lender Routing addon.")
	RegisterSystemEventHandler("SystemTimerElapsed", "Begin")
end

function Begin()
	local tns = GetTransactions()
	ProcessDataContexts("TransactionNumber", tns, "RouteFromAwaitingUniqueLender")
end

function GetTransactions()
	local connection = CreateManagedDatabaseConnection()
	local q = "select t.TransactionNumber "
	q = q .. "from Transactions t " 
	q = q .. "where t.TransactionStatus = 'Awaiting Unique Lender'"

	--retrieve tns from Unique lender queue

	connection.QueryString = q
	connection:Connect()
	local tns = connection:Execute()
	local UniqueLenderTNs = {}
	for i = 0, tns.Rows.Count - 1 do
		UniqueLenderTNs[i] = tns.Rows:get_Item(i)
	end

	table.sort(UniqueLenderTNs, compar)

	connection:Dispose()

	--retrieve tns that have just been checked in from customer

	q = "select t.TransactionNumber "
	q = q .. "from Transactions t, History h " 
	q = q .. "where t.TransactionStatus = 'Request Finished' "
	q = q .. "and t.TransactionNumber = h.TransactionNumber "
	q = q .. "and t.TransactionNumber in "
	q = q .. "(select TransactionNumber from History where TransactionNumber = t.TransactionNumber and Entry = 'Checked Out to Customer' and Datetime = CONVERT(VARCHAR(12),GETDATE(), 101)"

	connection.QueryString = q
	connection:Connect()
	tns = connection:Execute()
	local RequestFinishedTNs = {}
	for i = 0, tns.Rows.Count - 1 do
		RequestFinishedTNs[i] = tns.Rows:get_Item(i)
		LogDebug("Added from Unique Lender queue: " .. tns.Rows:get_Item(i):get_Item("TransactionNumber"))
	end

	connection:Dispose()

	local ReturnTNs = {}
	--no duplicates
	local flags = {}

	--find tns from recently checked in 
	--fix the logic of this!!!
	--or maybe it is fixed...?
	for i = 0, #RequestFinishedTNs - 1 do
		for j = 0, #UniqueLenderTNs - 1 do
			if (UniqueLenderTNs[i]:get_Item("Username") == RequestFinishedTNs[j].get_Item("Username") and UniqueLenderTNs[i]:get_Item("LendingLibrary") == RequestFinishedTNs[j]:get_Item("LendingLibrary") and
				not flags[ReturnTNs[j]:get_Item("TransactionNumber")) then
				table.insert(ReturnTNs, UniqueLenderTNs[i]:get_Item("TransactionNumber"))
				flags[ReturnTNs[j]:get_Item("TransactionNumber")] = true
				i = i + 1
				j = 0
			end
		end
	end

	return ReturnTNs
end

function RouteFromAwaitingUniqueLender()
	local tn = GetFieldValue("Transaction", "TransactionNumber")
	--Article, Book, Book Chapter, Conference, DVD, Document, Thesis,
	--Microform
	local docType = GetFieldValue("Transaction", "DocumentType")
	if docType == "Article" then
		ExecuteCommand("Route", {tn, "Article Request"})
	elseif docType == "Book" then
		ExecuteCommand("Route", {tn, "Book Request"})
	elseif docType == "Book Chapter" then
		ExecuteCommand("Route", {tn, "Book Chapter Request"})
	elseif docType == "Conference" then
		ExecuteCommand("Route", {tn, "Proceedings Request"})
	elseif docType == "DVD" then
		ExecuteCommand("Route", {tn, "Book Request"})
	elseif docType == "Document" then
		ExecuteCommand("Route", {tn, "Proceedings Request"})
	elseif docType == "Thesis" then
		ExecuteCommand("Route", {tn, "Dissertation Request"})
	elseif docType == "NPMicro" then
		ExecuteCommand("Route", {tn, "Microform Request: Newspaper"})
	elseif docType == "Microform" then
		ExecuteCommand("Route", {tn, "Microform Request: Other"})
	end
end

function compar(x, y)
	return x:get_Item("TransactionNumber") < y:get_Item("TransactionNumber")
end

