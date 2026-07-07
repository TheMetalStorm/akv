package kvstore

import "core:fmt"
import "core:os"
import "core:strings"
import "core:net"
import "base:runtime"

// TODO: return error codes for all functions instead of just bools and do not print messages.


// Data stored in file as "key1:value1;key2:value2"
KVStore :: struct {
    filepath: string,
    data: map[string]string
}

KEY_VAL_DELIMITER : string : ":"
KEY_VAL_DELIMITER_PERCENT_ENCODED : string : "%3A"
ENTRY_DELIMITER : string : ";"
ENTRY_DELIMITER_PERCENT_ENCODED : string : "%3B"

get_file :: proc(store: ^KVStore) -> ^os.File {
    file, err := os.open(store.filepath, flags = os.O_RDWR | os.O_CREATE, perm = os.Permissions_Read_Write_All)
    if err != os.ERROR_NONE {
        fmt.println("Could not open file %v \n Error: %v", store.filepath, err)
        return nil
    }
    return file
}

make_store :: proc(filepath:= "./store.db", allocator := context.allocator) -> (^KVStore, bool) {
    store, err := new(KVStore, allocator)
    if err != nil do return nil, false

    store.filepath = strings.clone(filepath, allocator)
    store.data = {} 

    ok := build_index(store)
    if !ok {
        fmt.println("Could not build index for store at", store.filepath)
        delete(store.filepath, allocator)
        free(store, allocator)
        return nil, false
    }

    return store, true
}

deallocate :: proc(store: ^KVStore){

    delete(store.filepath)
    for key, val in store.data{
        delete(key)
        delete(val)
    }
    delete(store.data)
    free(store, context.allocator)
    
}

build_index :: proc(store: ^KVStore) -> bool{

    file := get_file(store)
    defer os.close(file)

    data, read_err := os.read_entire_file(file, context.allocator)
    defer delete(data, context.allocator)
    if read_err != os.ERROR_NONE{
        return false
    }
    data_str := string(data)
    lines, err := strings.split(data_str, ";")
    defer delete(lines, context.allocator)

    if err != runtime.Allocator_Error.None{
        fmt.println("Something went wrong parsing KV store file. Error: ", err)
        return  false

    }

    for line in lines{
        entry, err := strings.split_n(line, ":", 2)
        
        if err != runtime.Allocator_Error.None{
            fmt.println("Something went wrong parsing KV store file. Error: ", err)
            return false
        }

        if len(entry) < 2 {
            delete(entry, context.allocator)
            continue
        }


        percent_decoded_key, ok := percent_decode(entry[0])
        if !ok {
            fmt.println("Something went wrong percent decoding key in KV store file. Key: ", entry[0])
            delete(entry, context.allocator)
            return false
        }
        defer delete(percent_decoded_key) 
        percent_decoded_val, ok2 := percent_decode(entry[1])
        if !ok2 {
            fmt.println("Something went wrong percent decoding value in KV store file. Value: ", entry[1])
            delete(entry, context.allocator)
            return false
        }
        defer delete(percent_decoded_val) 

        key := strings.clone(percent_decoded_key)
        value := strings.clone(percent_decoded_val)

        store.data[key] = value

        delete(entry, context.allocator)

    }

    return true

}

percent_encode :: proc(input: string) -> string {
    return net.percent_encode(input)

}

percent_decode :: proc(input: string) -> (string, bool) {
    return net.percent_decode(input)
}

// key_exists looks up if key exists in database.
key_exists :: proc(store: ^KVStore, key: string) -> bool {
    _, ok := store.data[key]
    return ok
}

// Returns:
// - value: The matching value string. Borrowed, do not free. 
// - found: If the key exists in the store
get_entry :: proc(store: ^KVStore , key: string) -> (string, bool) {
    return store.data[key]
}

// read looks up a key in the database file.
//
// If the key is found, it returns a value string 
// cloned from the file buffer. 

// Returns:
// - value: The matching value string. **The caller is responsible for freeing this 
// - found: If the key exists in the store
read :: proc (store: ^KVStore, key: string) -> (string, bool) {
    value, ok := store.data[key]
    if ok{
        return strings.clone(value), true
    }
    return "", false

}

// write inserts a key-value pair into the store.
//
// The key and value are copied into the store.
// The caller retains ownership of the original strings.
write :: proc (store: ^KVStore, key: string, value: string) -> bool {

    found := key_exists(store, key)
    
    if found {
        fmt.println("Key", key, "already exists in store")
        return false
    }

    store.data[strings.clone(key)] = strings.clone(value)
    return true

}

// Write the updated data in the Store to file
sync :: proc (store: ^KVStore) -> bool {

    file := get_file(store)
    defer os.close(file)

    new_lines := strings.builder_make_none()
    defer strings.builder_destroy(&new_lines)

    for key, val in store.data {
        encoded_key := percent_encode(key)
        encoded_val := percent_encode(val)

        strings.write_string(&new_lines, encoded_key)
        strings.write_string(&new_lines, KEY_VAL_DELIMITER)
        strings.write_string(&new_lines, encoded_val)
        strings.write_string(&new_lines, ENTRY_DELIMITER)
        delete(encoded_key) 
        delete(encoded_val) 
    }

    _, seek_err := os.seek(file, 0, .Start)
    if seek_err != os.ERROR_NONE{
        fmt.println("Something went wrong seeking in KV store file. Error: ", seek_err)
        return  false
    }
    trunc_err := os.truncate(file, 0)
    if trunc_err != os.ERROR_NONE{
        fmt.println("Something went wrong truncating KV store file. Error: ", trunc_err)
        return  false
    }
    _, write_err := os.write_string(file, strings.to_string(new_lines))
    if write_err != os.ERROR_NONE{
        fmt.println("Something went wrong writing to KV store file. Error: ", write_err)
        return  false
    }

    return true

}
// remove removes a key-value pair from the store.
remove :: proc (store: ^KVStore, key: string) -> bool{
    val, found := get_entry(store, key)

    if !found {
        fmt.println("Value for Key", key, "not found")    
        return false
    }
    
    kk, vk := delete_key(&store.data, key)
    delete(kk)
    delete(vk)
    
    return true
}
