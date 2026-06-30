package kvstore

import "core:fmt"
import "core:os"
import "core:strings"
import "base:runtime"

// stored in file as "key1:value1;key2:value2"
// TODO: zero copy version where map key and val are just slices into file data
// TODO: deal with delimiters in data!!
KVStore :: struct {
    filepath: string,
    // TODO: dealloc indices and strings 
    data: map[string]string
}

KEY_VAL_DELIMITER : string : ":"
ENTRY_DELIMITER : string : ";"

get_file :: proc(store: ^KVStore) -> ^os.File {
    file, err := os.open(store.filepath, flags = os.O_RDWR | os.O_CREATE, perm = os.Permissions_Read_Write_All)
    if err != os.ERROR_NONE {
        fmt.println("Could not open file %v \n Error: %v", store.filepath, err)
        return nil
    }
    return file
}

make_store :: proc(filepath:= "./store.db", allocator := context.allocator) -> (^KVStore, bool) {
    // 1. Allocate the KVStore on the heap so its pointer stays stable
    store, err := new(KVStore, allocator)
    if err != nil do return nil, false

    // 2. Clone the filepath using the same allocator
    store.filepath = strings.clone(filepath, allocator)
    store.data = {} // or whatever your initialization is

    // 3. Pass the stable heap pointer to build_index
    ok := build_index(store)
    if !ok {
        fmt.println("Could not build index for store at", store.filepath)
        // Clean up on failure to prevent leaks
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
        key := strings.clone(entry[0])
        value := strings.clone(entry[1])

        store.data[key] = value

        delete(entry, context.allocator)

    }

    return true

}

// key_exists looks up if key exists in database.

key_exists :: proc(store: ^KVStore, key: string) -> bool {
    _, ok := store.data[key]
    return ok
}

// get_entry looks up a key in the database file.
//
// If the key is found, it returns a value string 
// cloned from the file buffer. 

// Returns:
// - value: The matching value string. Borrowed, do not free. 
// - found: If the key exists in the store
get_entry :: proc(store: ^KVStore , key: string) -> (string, bool) {
    return store.data[key]
}

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
// Note: This procedure TAKES OWNERSHIP of the `key` and `value` strings. 
// Do not modify or free them after passing them in. The store will handle 
// their deallocation inside `dealloc`.
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
        strings.write_string(&new_lines, key)
        strings.write_string(&new_lines, KEY_VAL_DELIMITER)
        strings.write_string(&new_lines, val)
        strings.write_string(&new_lines, ENTRY_DELIMITER)
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
// del removes a key-value pair from the store.
// Warning: This procedure does not free the memory for the key and value strings.

del :: proc (store: ^KVStore, key: string) -> bool{
    val, found := read(store, key)
    if !found {
        fmt.println("Value for Key", key, "not found")    
        return false
    }
    delete(val)
    delete_key(&store.data, key)
    return true

}
