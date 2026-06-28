package kvstore

import "core:fmt"
import "core:os"
import "core:strings"
import "base:runtime"

// stored in file as "key1:value1;key2:value2"
KVStore :: struct {
    filepath: string
    // TODO: cache
    // TODO: compress and decompress data?
    // TODO: make thread safe
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

init :: proc(filepath: string) -> (KVStore, bool) {
    
    store: KVStore = KVStore{ filepath}

    return store, true
}

get_key_value :: proc(file: ^os.File, key: string) -> (string, bool) {

    data, read_err := os.read_entire_file(file, context.allocator)
    if read_err != os.ERROR_NONE{
        return "", false
    }
    data_str := strings.clone_from_bytes(data)
    lines, err := strings.split(data_str, ";")
    if err != runtime.Allocator_Error.None{
        fmt.println("Something went wrong parsing KV store file. Error: ", err)
        return  "", false
    }

    for line in lines{
        entry, err := strings.split_n(line, ":", 2)
        
        if err != runtime.Allocator_Error.None{
            fmt.println("Something went wrong parsing KV store file. Error: ", err)
            return  "", false
        }
        
        if entry[0] == key{
            return entry[1], true
        }

    }
    return "", false

}

write :: proc (store: ^KVStore, key: string, value: string) -> bool {
    file := get_file(store)
    defer os.close(file)
    _, found := get_key_value(file, key)
    
    if found {
        fmt.println("Key", key, "already exists in store")
        return false
    }


    n, e := os.write_strings(file, key, KEY_VAL_DELIMITER, value, ENTRY_DELIMITER)
    if e != os.ERROR_NONE{
        fmt.println("Could not write key", key, ": value" , value , " \n Error: ", e)
        return false
    }
    
    return true
}

delete :: proc (store: ^KVStore, key: string) -> bool{
    //TODO
    return false
}

read :: proc (store: ^KVStore, key: string) -> (string, bool) {

    file := get_file(store)
    defer os.close(file)
    val, found := get_key_value(file, key)
    if found {
        fmt.println("Value for Key", key, "found")    
        return val, true
    }
    fmt.println("Value for Key", key, "not found")
    return "", false

}