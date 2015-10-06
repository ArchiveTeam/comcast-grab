dofile("urlcode.lua")
dofile("table_show.lua")

local url_count = 0
local tries = 0
local item_type = os.getenv('item_type')
local item_value = os.getenv('item_value')

local downloaded = {}
local addedtolist = {}

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]
  
  if downloaded[url] == true or addedtolist[url] == true then
    return false
  end
  
  if downloaded[url] ~= true and addedtolist[url] ~= true then
    if string.match(url, "home%.comcast%.") or string.match(url, "comcastbiz%.") or html == 0 then
      addedtolist[url] = true
      return true
    else
      return false
    end
  end
end


wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil

  downloaded[url] = true
  
  local function check(urla)
    local url = string.match(urla, "^([^#]+)")
    if (downloaded[url] ~= true and addedtolist[url] ~= true) and (string.match(url, "^https://[^/]*home%.comcast%.[^/]*") or string.match(url, "^https://[^/]*comcastbiz%.[^/]*")) then
      if string.match(url, "&amp;") then
        table.insert(urls, { url=string.gsub(url, "&amp;", "&") })
        addedtolist[url] = true
        addedtolist[string.gsub(url, "&amp;", "&")] = true
      else
        table.insert(urls, { url=url })
        addedtolist[url] = true
      end
    end
  end

  local function checknewurl(newurl)
    if string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^//") then
      check("http:"..newurl)
    elseif string.match(newurl, "^/") then
      check(string.match(url, "^(https?://[^/]+)")..newurl)
    elseif string.match(newurl, "%.jpg$") or string.match(newurl, "%.gif$") then
      check(string.match(url, "^(https?://[^/]+/)")..newurl)
    end
  end
  
  if (string.match(url, "^https?://[^/]*home%.comcast%.[^/]*") or string.match(url, "^https?://[^/]*comcastbiz%.[^/]*")) and not (string.match(url, "%.mp4$") or string.match(url, "%.jpg$") or string.match(url, "%.gif$") or string.match(url, "%.avi$") or string.match(url, "%.flv$") or string.match(url, "%.pdf$") or string.match(url, "%.rm$") or string.match(url, "%.wmv$") or string.match(url, "%.jpeg$") or string.match(url, "%.swf$")) then
    html = read_file(file)
    check(string.match(url, "^(https?://.+/)"))
    check(string.match(url, "^(https?://.+)/"))
    check(string.match(url, "^(https?://[^%?]+)"))
    check(string.match(url, "^(https?://[^&]+)"))
    for newurl in string.gmatch(html, '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">([^<]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "location='([^']+)'") do
      if not (string.match(newurl, "^/") or string.match(newurl, "^https?://")) then
        check(string.match(url, "^(https?://[^/]+/)")..newurl)
      end
    end
    for newurl in string.gmatch(html, 'href="([^"]+)"') do
      if not (string.match(newurl, "^/") or string.match(newurl, "^https?://")) then
        check(string.match(url, "^(https?://[^/]+/)")..newurl)
      end
    end
    if string.match(url, "^https?://[^%.]+%.home.comcast.net/~") then
      check(string.match(url, "^(https?://[^/]+)/~")..string.match(url, "^https?://[^/]+/~[^/]+(.*)"))
    end
    if string.match(url, "^https?://.+/[^/]+/") then
      check(string.match(url, "^(https?://.+/)[^/]+/"))
      check(string.match(url, "^(https?://.+)/[^/]+/"))
    end
  end
  
  return urls
end
  

wget.callbacks.httploop_result = function(url, err, http_stat)
  -- NEW for 2014: Slightly more verbose messages because people keep
  -- complaining that it's not moving or not working
  status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. ".  \n")
  io.stdout:flush()

  if downloaded[url["url"]] == true then
    return wget.actions.EXIT
  end

  if (status_code >= 200 and status_code <= 399) then
    if string.match(url.url, "https://") then
      local newurl = string.gsub(url.url, "https://", "http://")
      downloaded[newurl] = true
    else
      downloaded[url.url] = true
    end
  end
  
  if status_code >= 500 or
    (status_code >= 400 and status_code ~= 404 and status_code ~= 403 and status_code ~= 400 and status_code ~= 414) then
    io.stdout:write("\nServer returned "..http_stat.statcode..". Sleeping.\n")
    io.stdout:flush()
    os.execute("sleep 1")
    tries = tries + 1
    if tries >= 5 then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if (item_type == "comcasthomea" and string.match(url["url"], "^https?://home%.comcast%.net/~")) or (item_type == "acomcasthome" and string.match(url["url"], "^https?://[^%.]+%.home%.comcast%.net")) or (item_type == "comcastbiznet" and string.match(url["url"], "^https?://[^%.]+%.comcastbiz%.net")) or (item_type == "comcastbiznet" and string.match(url["url"], "^https?://[^%.]+%.comcastbiz%.com")) then
        return wget.actions.EXIT
      else
        return wget.actions.EXIT
      end
    else
      return wget.actions.CONTINUE
    end
  elseif status_code == 0 then
    if string.match(url["url"], "https?://rss%.thingiverse%.com") then
      return wget.actions.EXIT
    end
    io.stdout:write("\nServer returned "..http_stat.statcode..". Sleeping.\n")
    io.stdout:flush()
    os.execute("sleep 10")
    tries = tries + 1
    if tries >= 5 then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if (item_type == "comcasthomea" and string.match(url["url"], "^https?://home%.comcast%.net/~")) or (item_type == "acomcasthome" and string.match(url["url"], "^https?://[^%.]+%.home%.comcast%.net")) or (item_type == "comcastbiznet" and string.match(url["url"], "^https?://[^%.]+%.comcastbiz%.net")) or (item_type == "comcastbiznet" and string.match(url["url"], "^https?://[^%.]+%.comcastbiz%.com")) then
        return wget.actions.EXIT
      else
        return wget.actions.EXIT
      end
    else
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end
