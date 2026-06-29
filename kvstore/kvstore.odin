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

dealloc_entry :: proc(entry: KVEntry) {
    delete(entry.key, context.allocator)
    delete(entry.value, context.allocator)
}

// get_KVEntry looks up a key in the database file.
//
// If the key is found, it returns a KVEntry containing newly allocated strings 
// cloned from the file buffer. 

// Returns:
// - entry: The matching record. **The caller is responsible for freeing this 
//   memory by calling `dealloc_entry(entry, allocator)`.**
get_KVEntry :: proc(file: ^os.File, key: string) -> (KVEntry, bool) {
    data, read_err := os.read_entire_file(file, context.allocator)
    defer delete(data, context.allocator)
    if read_err != os.ERROR_NONE{
        return {}, false
    }
    data_str := string(data)
    lines, err := strings.split(data_str, ";")
    defer delete(lines, context.allocator)

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

        if len(entry) < 2 {
            delete(entry, context.allocator)
            continue
        }

        
        if entry[0] == key{

            ret := KVEntry{ strings.clone(entry[0]), strings.clone(entry[1]), key_start_pos}
            delete(entry, context.allocator)
            return ret, true

        }
        key_start_pos += len(line) + 1
        delete(entry, context.allocator)

    }
    return {}, false


}

write :: proc (store: ^KVStore, key: string, value: string) -> bool {
    file := get_file(store)
    defer os.close(file)
    entry, found := get_KVEntry(file, key)
    
    if found {
        fmt.println("Key", key, "already exists in store")
        dealloc_entry(entry)
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

read :: proc (store: ^KVStore, key: string) -> (KVEntry, bool) {

    file := get_file(store)
    defer os.close(file)
    entry, found := get_KVEntry(file, key)
    if found {
        fmt.println("Value for Key", key, "found")    
        return entry, true
    }
    dealloc_entry(entry)
    fmt.println("Value for Key", key, "not found")
    return {}, false

}

del :: proc{
    delete_by_key,
    delete_by_kv_entry
}



delete_by_key :: proc (store: ^KVStore, key: string) -> bool{
    file := get_file(store)
    defer os.close(file)
    val, found := get_KVEntry(file, key)
    if !found {
        fmt.println("Value for Key", key, "not found")    
        return false
    }

    return delete_by_kv_entry(store, val)
}

delete_by_kv_entry :: proc (store: ^KVStore, kv_entry: KVEntry) -> bool{
    defer dealloc_entry(kv_entry)
    file := get_file(store)
    defer os.close(file)
    data, read_err := os.read_entire_file(file, context.allocator)
    defer delete(data, context.allocator)

    if read_err != os.ERROR_NONE{
        return  false
    }
    data_str := string(data)

    lines, err := strings.split(data_str, ";")
    defer delete(lines, context.allocator)
    if err != runtime.Allocator_Error.None{
        fmt.println("Something went wrong parsing KV store file. Error: ", err)
        return  false

    }

    new_lines := strings.builder_make_none()
    defer strings.builder_destroy(&new_lines)

    for line in lines{
        if line == ""{
            continue
        }
        entry, err := strings.split_n(line, ":", 2)
        
        if err != runtime.Allocator_Error.None{
            fmt.println("Something went wrong parsing KV store file. Error: ", err)
            delete(entry, context.allocator)

            return  false
        }
        
        if len(entry) < 2 {
            delete(entry, context.allocator)
            continue
        }


        if strings.compare(entry[0], kv_entry.key) != 0{
            strings.write_string(&new_lines, line)
            strings.write_string(&new_lines, ENTRY_DELIMITER)
        }
        delete(entry, context.allocator)

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

    fmt.println("Deleted key", kv_entry.key, "from store")


    return true
}

