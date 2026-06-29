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

KVEntry :: struct{
    key: string,
    value: string,
    start_pos: int
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



//TODO very heavy, maybe one method to check if key exists and one to actually get val? research
get_KVEntry :: proc(file: ^os.File, key: string) -> (KVEntry, bool) {
    data, read_err := os.read_entire_file(file, context.allocator)
    if read_err != os.ERROR_NONE{
        return {}, false
    }
    data_str := strings.clone_from_bytes(data)
    lines, err := strings.split(data_str, ";")
    if err != runtime.Allocator_Error.None{
        fmt.println("Something went wrong parsing KV store file. Error: ", err)
        return {}, false

    }

    key_start_pos := 0

    for line in lines{
        entry, err := strings.split_n(line, ":", 2)
        
        if err != runtime.Allocator_Error.None{
            fmt.println("Something went wrong parsing KV store file. Error: ", err)
            return {}, false
        }
        
        if entry[0] == key{
            return { entry[0], entry[1], key_start_pos}, true
        }
        key_start_pos += len(line) + 1

    }
    return {}, false


}

write :: proc (store: ^KVStore, key: string, value: string) -> bool {
    file := get_file(store)
    defer os.close(file)
    _, found := get_KVEntry(file, key)
    
    if found {
        fmt.println("Key", key, "already exists in store")
        return false
    }


    n, e := os.write_strings(file, key, KEY_VAL_DELIMITER, value, ENTRY_DELIMITER)
    if e != os.ERROR_NONE{
        fmt.println("Could not write key", key, ": value" , value , " \n Error: ", e)
        return false
    }

    fmt.println("Wrote Key", key)
    return true
}

// delete :: proc (store: ^KVStore, key: string) -> bool{
//         file := get_file(store)
//     defer os.close(file)
//     val, found := get_KVEntry(file, key)
//     if !found {
//         fmt.println("Value for Key", key, "not found")    
//         return false
//     }

//     return true
// }

delete :: proc (store: ^KVStore, kv_entry: KVEntry) -> bool{
    file := get_file(store)
    defer os.close(file)
    data, read_err := os.read_entire_file(file, context.allocator)
    if read_err != os.ERROR_NONE{
        return  false
    }
    data_str := strings.clone_from_bytes(data)
    lines, err := strings.split(data_str, ";")
    if err != runtime.Allocator_Error.None{
        fmt.println("Something went wrong parsing KV store file. Error: ", err)
        return  false

    }

    new_lines := strings.builder_make_none()
    fmt.println(strings.to_string(new_lines))
    for line in lines{
        if line == ""{
            continue
        }
        entry, err := strings.split_n(line, ":", 2)
        
        if err != runtime.Allocator_Error.None{
            fmt.println("Something went wrong parsing KV store file. Error: ", err)
            return  false
        }
        fmt.println(entry[0])
        fmt.println(kv_entry.key)

        if strings.compare(entry[0], kv_entry.key) != 0{
            fmt.println(line)
            strings.write_string(&new_lines, line)
            strings.write_string(&new_lines, ENTRY_DELIMITER)
        }
    }

    os.seek(file, 0, .Start)
    os.truncate(file, 0)
    fmt.println(strings.to_string(new_lines))
    os.write_string(file,   strings.to_string(new_lines))

    return true
}

read :: proc (store: ^KVStore, key: string) -> (KVEntry, bool) {

    file := get_file(store)
    defer os.close(file)
    entry, found := get_KVEntry(file, key)
    if found {
        fmt.println("Value for Key", key, "found")    
        return entry, true
    }
    fmt.println("Value for Key", key, "not found")
    return {}, false

}