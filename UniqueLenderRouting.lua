-- Automatically moves requests to appropriate queues based on transition 
-- from Checked out to Customer to Request Finished, if the two requests 
-- have the same (unique) lender.

--Author: Michael McGlinchey, Bowdoin College, 2015

local flags
local Unique_tns
local Returned_tns
local RequestFinishedTNs
local UniqueLenderTNs
local uniq_len
local retd_len

function Init()
	LogDebug("Initializing Unique Lender Routing addon.")
	RegisterSystemEventHandler("SystemTimerElapsed", "Begin")
end

function Begin()
	flags = {}
	Unique_tns = {}
	Returned_tns = {}
	RequestFinishedTNs = {}
	UniqueLenderTNs = {}
	uniq_len = 0
	retd_len = 0
	Unique_tns = GetUniqueTransactions()
	Returned_tns = GetReturnedTransactions()
	if (Unique_tns ~= {} and Returned_tns ~= {}) then
		local tns = ProcessTransactions()
		ProcessDataContexts("TransactionNumber", tns, "RouteFromAwaitingUniqueLender")
	end
end

function GetUniqueTransactions()
	LogDebug("Getting unique lender tns.")
	local connection = CreateManagedDatabaseConnection()
	local q = "select TransactionNumber, LendingLibrary, Username "
	q = q .. "from Transactions t " 
	q = q .. "where t.TransactionStatus = 'Awaiting Unique Lender'"

	--retrieve tns from Unique lender queue

	connection.QueryString = q
	connection:Connect()
	local tns = connection:Execute()

	for i = 0, tns.Rows.Count - 1 do
		UniqueLenderTNs[i] = tns.Rows:get_Item(i)
		uniq_len = uniq_len + 1
	end

	connection:Dispose()

	table.sort(UniqueLenderTNs, compar)

	return UniqueLenderTNs
end

function GetReturnedTransactions()
	LogDebug("Getting returned recently tns.")
	local connection = CreateManagedDatabaseConnection()
	local q = "select TransactionNumber, LendingLibrary, Username "
	q = q .. "from Transactions t where t.RequestType = 'Loan' " 
	q = q .. "and t.TransactionStatus = 'Request Finished' "
	q = q .. "and t.Username != 'Lending' "
	q = q .. "and DATEDIFF(mi, t.TransactionDate, GETDATE()) < 2"

	--retrieve tns that have been ret'd today

	connection.QueryString = q
	connection:Connect()
	local tns = connection:Execute()


	for i = 0, tns.Rows.Count - 1 do
		RequestFinishedTNs[i] = tns.Rows:get_Item(i)
		flags[RequestFinishedTNs[i]:get_Item("TransactionNumber")] = false
		retd_len = retd_len + 1	
	end

	connection:Dispose()

	return RequestFinishedTNs
end

function ProcessTransactions()
	LogDebug("Processing unique/rec.ret tns")
	
	local ReturnTNs = {}
	
	for i = 0, uniq_len - 1 do
		for j = 0, retd_len - 1 do
			if (RequestFinishedTNs[j]:get_Item("Username") == UniqueLenderTNs[i]:get_Item("Username") and RequestFinishedTNs[j]:get_Item("LendingLibrary") == UniqueLenderTNs[i]:get_Item("LendingLibrary") and flags[RequestFinishedTNs[j]:get_Item("TransactionNumber")] ~= true) then
					table.insert(ReturnTNs, UniqueLenderTNs[i]:get_Item("TransactionNumber"))
					flags[RequestFinishedTNs[j]:get_Item("TransactionNumber")] = true
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
	if docType == "Book" then
		ExecuteCommand("Route", {tn, "Book Request"})
	elseif docType == "Book Chapter" then
		ExecuteCommand("Route", {tn, "Book Chapter Request"})
	elseif docType == "DVD" then
		ExecuteCommand("Route", {tn, "Book Request"})
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

