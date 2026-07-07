package kvstore

import "core:os"
import "core:strings"
import "core:net"
import "base:runtime"

// Data stored in file as "key1:value1;key2:value2"
KVStore :: struct {
    filepath: string,
    data: map[string]string
}

Store_Error :: enum {
	None = 0,
	File_Error,
	Could_Not_Create_Store_Error,
    Indexing_Error,
    Decoding_Error,
    Parsing_Error,
    Key_Not_Found_Error,
    Sync_Error,
    Key_Already_Exists_Error
}


KEY_VAL_DELIMITER : string : ":"
KEY_VAL_DELIMITER_PERCENT_ENCODED : string : "%3A"
ENTRY_DELIMITER : string : ";"
ENTRY_DELIMITER_PERCENT_ENCODED : string : "%3B"

get_file :: proc(store: ^KVStore) -> (^os.File, Store_Error) {
    file, err := os.open(store.filepath, flags = os.O_RDWR | os.O_CREATE, perm = os.Permissions_Read_Write_All)
    if err != os.ERROR_NONE {
        return nil, Store_Error.File_Error
    }
    return file, Store_Error.None
}

make_store :: proc(filepath:= "./store.db", allocator := context.allocator) -> (^KVStore, Store_Error) {
    store, err := new(KVStore, allocator)
    if err != nil do return nil, Store_Error.Could_Not_Create_Store_Error

    store.filepath = strings.clone(filepath, allocator)
    store.data = {} 

    store_err := build_index(store)
    if store_err != Store_Error.None {
        deallocate(store)
        return nil, store_err
    }

    return store, Store_Error.None
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

build_index :: proc(store: ^KVStore) -> Store_Error {

    file, err := get_file(store)
    defer os.close(file)

    if err != Store_Error.None {
        return err
    }

    data, read_err := os.read_entire_file(file, context.allocator)
    defer delete(data, context.allocator)
    if read_err != os.ERROR_NONE{
        return Store_Error.File_Error
    }
    data_str := string(data)
    lines, alloc_err := strings.split(data_str, ";")
    defer delete(lines, context.allocator)

    if alloc_err != runtime.Allocator_Error.None{
        return Store_Error.Parsing_Error

    }

    for line in lines{
        entry, err := strings.split_n(line, ":", 2)
        
        if err != runtime.Allocator_Error.None{
            return Store_Error.Parsing_Error
        }

        if len(entry) < 2 {
            delete(entry, context.allocator)
            continue
        }


        percent_decoded_key, ok := percent_decode(entry[0])
        if !ok {
            delete(entry, context.allocator)
            return Store_Error.Decoding_Error
        }
        defer delete(percent_decoded_key) 
        percent_decoded_val, ok2 := percent_decode(entry[1])
        if !ok2 {
            delete(entry, context.allocator)
            return Store_Error.Decoding_Error
        }
        defer delete(percent_decoded_val) 

        key := strings.clone(percent_decoded_key)
        value := strings.clone(percent_decoded_val)

        store.data[key] = value

        delete(entry, context.allocator)

    }

    return Store_Error.None

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
read :: proc (store: ^KVStore, key: string) -> (string, Store_Error) {
    value, ok := store.data[key]
    if ok{
        return strings.clone(value), Store_Error.None
    }
    return "", Store_Error.Key_Not_Found_Error

}

// write inserts a key-value pair into the store.
//
// The key and value are copied into the store.
// The caller retains ownership of the original strings.
write :: proc (store: ^KVStore, key: string, value: string) -> Store_Error {

    found := key_exists(store, key)
    
    if found {
        return Store_Error.Key_Already_Exists_Error
    }

    store.data[strings.clone(key)] = strings.clone(value)
    return Store_Error.None

}

// Write the updated data in the Store to file
sync :: proc (store: ^KVStore) -> Store_Error {

    file, err := get_file(store)
    if err != Store_Error.None {
        return err
    }
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
        return  Store_Error.Sync_Error
    }
    trunc_err := os.truncate(file, 0)
    if trunc_err != os.ERROR_NONE{
        return  Store_Error.Sync_Error
    }
    _, write_err := os.write_string(file, strings.to_string(new_lines))
    if write_err != os.ERROR_NONE{
        return  Store_Error.Sync_Error
    }

    return Store_Error.None

}
// remove removes a key-value pair from the store.
remove :: proc (store: ^KVStore, key: string) -> Store_Error{
    val, found := get_entry(store, key)

    if !found {
        return Store_Error.Key_Not_Found_Error
    }
    
    kk, vk := delete_key(&store.data, key)
    delete(kk)
    delete(vk)
    
    return Store_Error.None
}
