package kvstore

import "core:fmt"
import "core:os"
import "core:strings"
import "base:runtime"

// stored in file as "key1:value1;key2:value2"
KVStore :: struct {
    file: ^os.File
    // TODO: cache
    // TODO: compress and decompress data?
    // TODO: make thread safe
}

KEY_VAL_DELIMITER : string : ":"
ENTRY_DELIMITER : string : ";"

init :: proc(filepath: string) -> (KVStore, bool) {
    
    file: ^os.File
    err: os.Error
 
    file, err = os.open(filepath, flags = os.O_RDWR | os.O_CREATE, perm = os.Permissions_Read_Write_All)
    if err != os.ERROR_NONE {
        fmt.println("Could not open file %v \n Error: %v", filepath, err)
        return KVStore{}, false
    }
    fmt.println("Found KV Store at ", filepath)
    

    store: KVStore = KVStore{file}

    return store, true
}



write :: proc (store: ^KVStore, key: string, value: string) -> bool {
    //TODO dont do this on every read / write
    data, read_err := os.read_entire_file(store.file, context.allocator)
    if read_err != os.ERROR_NONE{
        return false
    }
    data_str := strings.clone_from_bytes(data)
    lines, err := strings.split(data_str, ";")
    if err != runtime.Allocator_Error.None{
        fmt.println("Could not write key ", key, ": value " , value , " \n Error: ", err)
        return false
    }

    for line in lines{
        entry, err := strings.split_n(line, ":", 2)
        if err != runtime.Allocator_Error.None{
            //TODO: better message
            fmt.println("Something went wrong : %v", err)
            return false
        }
        if entry[0] == key{
            fmt.println("Key \"", key, "\" already exists in store")
            return false
        }
    }


    n, e := os.write_strings(store.file, key, KEY_VAL_DELIMITER, value, ENTRY_DELIMITER)
    if e != os.ERROR_NONE{
        fmt.println("Could not write key ", key, ": value " , value , " \n Error: ", e)
        return false
    }
    os.flush(store.file)
    
    return true
}

delete :: proc (store: ^KVStore, key: string) -> bool{
    //TODO
    return false
}

read :: proc (store: ^KVStore, key: string) -> (string, bool) {
    // Check if key exist
    // if yes, notify user
    // if not, return value
    //   split by line, then every line by : and check if correct key
    return "", false
}