-- Gree Protocol Crypto Module
-- AES encryption/decryption for Gree WiFi protocol
-- Based on: https://github.com/bekmansurov/gree-hvac-protocol

local log = package.loaded.log or require "log"
local base64 = package.loaded["st.base64"] or {
  encode = function(data)
    local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    return ((data:gsub('.', function(x) 
        local r,b='',x:byte()
        for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
        return r;
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b64chars:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
  end,
  decode = function(data)
    local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    data = string.gsub(data, '[^'..b64chars..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',(b64chars:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r;
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
  end
}

local crypto = {}

-- Generic AES key (used before binding)
crypto.GENERIC_KEY = "a3K8Bx%2r8Y7#xDh"

-- AES ECB encryption using OpenSSL
-- Note: Gree uses AES-128-ECB with PKCS7 padding
local function aes_encrypt(data, key)
  -- Pad data to 16-byte blocks (PKCS7 padding)
  local padding = 16 - (#data % 16)
  local padded_data = data .. string.rep(string.char(padding), padding)
  
  -- Use openssl for encryption via command line (temporary approach)
  -- TODO: Replace with pure Lua AES implementation or SmartThings crypto library
  local temp_in = os.tmpname()
  local temp_out = os.tmpname()
  local temp_key = os.tmpname()
  
  local f = io.open(temp_in, "wb")
  f:write(padded_data)
  f:close()
  
  f = io.open(temp_key, "w")
  f:write(key)
  f:close()
  
  -- Run openssl encryption
  local cmd = string.format(
    "openssl enc -aes-128-ecb -in %s -out %s -K $(echo -n '%s' | xxd -p) -nopad",
    temp_in, temp_out, key
  )
  os.execute(cmd)
  
  -- Read encrypted result
  f = io.open(temp_out, "rb")
  local encrypted = f:read("*all")
  f:close()
  
  -- Cleanup
  os.remove(temp_in)
  os.remove(temp_out)
  os.remove(temp_key)
  
  return encrypted
end

-- AES ECB decryption using OpenSSL
local function aes_decrypt(data, key)
  local temp_in = os.tmpname()
  local temp_out = os.tmpname()
  
  local f = io.open(temp_in, "wb")
  f:write(data)
  f:close()
  
  -- Run openssl decryption
  local cmd = string.format(
    "openssl enc -aes-128-ecb -d -in %s -out %s -K $(echo -n '%s' | xxd -p) -nopad",
    temp_in, temp_out, key
  )
  os.execute(cmd)
  
  -- Read decrypted result
  f = io.open(temp_out, "rb")
  local decrypted = f:read("*all")
  f:close()
  
  -- Remove PKCS7 padding
  local padding = string.byte(decrypted, -1)
  if padding and padding > 0 and padding <= 16 then
    decrypted = decrypted:sub(1, -padding - 1)
  end
  
  -- Cleanup
  os.remove(temp_in)
  os.remove(temp_out)
  
  return decrypted
end

-- Encrypt and encode message for Gree protocol
function crypto.encrypt(plain_text, key)
  key = key or crypto.GENERIC_KEY
  
  log.debug("Encrypting message with key: " .. key)
  
  local encrypted = aes_encrypt(plain_text, key)
  local encoded = base64.encode(encrypted)
  
  log.debug("Encrypted result: " .. encoded)
  
  return encoded
end

-- Decode and decrypt message from Gree protocol
function crypto.decrypt(encrypted_text, key)
  key = key or crypto.GENERIC_KEY
  
  log.debug("Decrypting message with key: " .. key)
  
  local decoded = base64.decode(encrypted_text)
  local decrypted = aes_decrypt(decoded, key)
  
  log.debug("Decrypted result: " .. decrypted)
  
  return decrypted
end

return crypto