-- Pure Lua AES-128-GCM helper built on top of the existing AES-128 block cipher.

local aes128 = require "aes128"

local aes_gcm = {}

local function bytes_from_string(value)
  local bytes = {}
  for index = 1, #value do
    bytes[index] = value:byte(index)
  end
  return bytes
end

local function bytes_to_string(bytes, length)
  local chars = {}
  local limit = length or #bytes
  for index = 1, limit do
    chars[index] = string.char(bytes[index] or 0)
  end
  return table.concat(chars)
end

local function zero_block()
  local block = {}
  for index = 1, 16 do
    block[index] = 0
  end
  return block
end

local function copy_block(block)
  local copy = {}
  for index = 1, #block do
    copy[index] = block[index]
  end
  return copy
end

local function xor_blocks(left, right)
  local result = {}
  for index = 1, 16 do
    result[index] = ((left[index] or 0) ~ (right[index] or 0)) & 0xFF
  end
  return result
end

local function chunk_to_block(data, start_index)
  local block = {}
  for offset = 0, 15 do
    block[offset + 1] = data:byte(start_index + offset) or 0
  end
  return block
end

local function shift_right_one(block)
  local shifted = {}
  local carry = 0

  for index = 1, 16 do
    local value = block[index]
    shifted[index] = ((value >> 1) | carry) & 0xFF
    carry = ((value & 0x01) << 7) & 0xFF
  end

  return shifted
end

local function multiply_blocks(x_block, y_block)
  local z_block = zero_block()
  local v_block = copy_block(y_block)

  for byte_index = 1, 16 do
    local byte_value = x_block[byte_index]
    for bit_index = 7, 0, -1 do
      if ((byte_value >> bit_index) & 0x01) ~= 0 then
        z_block = xor_blocks(z_block, v_block)
      end

      local lsb = v_block[16] & 0x01
      v_block = shift_right_one(v_block)
      if lsb ~= 0 then
        v_block[1] = (v_block[1] ~ 0xE1) & 0xFF
      end
    end
  end

  return z_block
end

local function append_uint64_be(bytes, start_index, value)
  for offset = 7, 0, -1 do
    bytes[start_index + (7 - offset)] = (value >> (offset * 8)) & 0xFF
  end
end

local function ghash(hash_subkey, additional_data, cipher_text)
  local accumulator = zero_block()
  local hash_bytes = bytes_from_string(hash_subkey)

  local function process_blocks(data)
    for start_index = 1, #data, 16 do
      accumulator = multiply_blocks(
        xor_blocks(accumulator, chunk_to_block(data, start_index)),
        hash_bytes
      )
    end
  end

  if #additional_data > 0 then
    process_blocks(additional_data)
  end

  if #cipher_text > 0 then
    process_blocks(cipher_text)
  end

  local length_block = zero_block()
  append_uint64_be(length_block, 1, #additional_data * 8)
  append_uint64_be(length_block, 9, #cipher_text * 8)

  accumulator = multiply_blocks(xor_blocks(accumulator, length_block), hash_bytes)

  return bytes_to_string(accumulator, 16)
end

local function encrypt_block(block, key)
  return aes128.encrypt_ecb(block, key)
end

local function increment_counter(counter_block)
  local counter = copy_block(counter_block)

  for index = 16, 13, -1 do
    counter[index] = (counter[index] + 1) & 0xFF
    if counter[index] ~= 0 then
      break
    end
  end

  return counter
end

local function gctr(key, initial_counter, data)
  if #data == 0 then
    return ""
  end

  local counter = copy_block(initial_counter)
  local encrypted = {}

  for start_index = 1, #data, 16 do
    local block = data:sub(start_index, start_index + 15)
    local keystream = encrypt_block(bytes_to_string(counter, 16), key)
    local chars = {}

    for offset = 1, #block do
      chars[offset] = string.char((block:byte(offset) ~ keystream:byte(offset)) & 0xFF)
    end

    encrypted[#encrypted + 1] = table.concat(chars)
    counter = increment_counter(counter)
  end

  return table.concat(encrypted)
end

local function compute_j0(iv)
  if #iv ~= 12 then
    error("AES-GCM helper expects a 12-byte IV, got " .. #iv)
  end

  local counter = bytes_from_string(iv)
  counter[13] = 0
  counter[14] = 0
  counter[15] = 0
  counter[16] = 1
  return counter
end

local function verify_tag(left, right)
  if #left ~= #right then
    return false
  end

  local diff = 0
  for index = 1, #left do
    diff = diff | ((left:byte(index) ~ right:byte(index)) & 0xFF)
  end

  return diff == 0
end

function aes_gcm.encrypt(plain_text, key, iv, additional_data)
  if #key ~= 16 then
    error("AES-GCM requires a 16-byte key, got " .. #key)
  end

  local aad = additional_data or ""
  local j0 = compute_j0(iv)
  local hash_subkey = encrypt_block(string.rep("\0", 16), key)
  local cipher_text = gctr(key, increment_counter(j0), plain_text)
  local auth_block = ghash(hash_subkey, aad, cipher_text)
  local tag = gctr(key, j0, auth_block)

  return cipher_text, tag
end

function aes_gcm.decrypt(cipher_text, tag, key, iv, additional_data)
  if #key ~= 16 then
    error("AES-GCM requires a 16-byte key, got " .. #key)
  end

  local aad = additional_data or ""
  local j0 = compute_j0(iv)
  local hash_subkey = encrypt_block(string.rep("\0", 16), key)
  local auth_block = ghash(hash_subkey, aad, cipher_text)
  local expected_tag = gctr(key, j0, auth_block)

  if not verify_tag(expected_tag, tag) then
    return nil, "Authentication failed"
  end

  return gctr(key, increment_counter(j0), cipher_text)
end

return aes_gcm