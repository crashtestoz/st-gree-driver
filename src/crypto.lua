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

-- Use pure Lua AES-128-ECB implementation (st.security doesn't support AES-128)
local aes128 = require "aes128"

-- AES ECB encryption using pure Lua implementation
-- Note: Gree uses AES-128-ECB with PKCS7 padding
local function aes_encrypt(data, key)
  log.debug("Encrypting with pure Lua AES-128-ECB, data length: " .. #data)
  
  if #key ~= 16 then
    log.error("AES-128 requires 16-byte key, got " .. #key)
    return nil
  end
  
  -- Pad data to 16-byte blocks (PKCS7 padding)
  local padding = 16 - (#data % 16)
  local padded_data = data .. string.rep(string.char(padding), padding)
  
  log.debug("After padding, length: " .. #padded_data)
  
  -- Encrypt using pure Lua AES-128
  local success, encrypted = pcall(aes128.encrypt_ecb, padded_data, key)
  
  if not success then
    log.error("AES encryption failed: " .. tostring(encrypted))
    return nil
  end
  
  log.debug("Encryption successful, result length: " .. #encrypted)
  
  return encrypted
end

-- AES ECB decryption using pure Lua implementation
-- Gree protocol: AES-128-ECB with PKCS7 padding, then Base64 encoding
local function aes_decrypt(data, key)
  log.debug("Decrypting with pure Lua AES-128-ECB")
  log.debug("Data length: " .. #data .. ", Key length: " .. #key)
  
  if #key ~= 16 then
    log.error("AES-128 requires 16-byte key, got " .. #key)
    return nil
  end
  
  if #data % 16 ~= 0 then
    log.error("Encrypted data length must be multiple of 16, got " .. #data)
    return nil
  end
  
  -- Decrypt using pure Lua AES-128
  local success, decrypted = pcall(aes128.decrypt_ecb, data, key)
  
  if not success then
    log.error("AES decryption failed: " .. tostring(decrypted))
    return nil
  end
  
  log.debug("Decryption successful, result length: " .. #decrypted)
  
  -- Remove PKCS7 padding
  if #decrypted > 0 then
    local padding = decrypted:byte(-1)
    log.debug("PKCS7 padding value: " .. padding)
    if padding and padding > 0 and padding <= 16 then
      -- Verify padding is valid (all padding bytes should be same)
      local valid = true
      for i = 1, padding do
        if decrypted:byte(-i) ~= padding then
          valid = false
          break
        end
      end
      
      if valid then
        decrypted = decrypted:sub(1, -padding - 1)
        log.debug("After removing padding, length: " .. #decrypted)
      else
        log.warn("Invalid PKCS7 padding detected, not removing")
      end
    end
  end
  
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
  log.debug("Base64 decoded length: " .. #decoded)
  
  local decrypted = aes_decrypt(decoded, key)
  
  if decrypted then
    log.debug("Decrypted result length: " .. #decrypted)
    log.trace("Decrypted result: " .. decrypted)
  else
    log.error("Decryption returned nil")
    return nil
  end
  
  return decrypted
end

return crypto