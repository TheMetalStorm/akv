package kvstore

import "core:os"
import "core:strings"
import "core:net"
import "base:runtime"
import "core:sync"
import "core:fmt"

// NOTE: Data stored in file on disk as "key1:value1;key2:value2". Keys and values are percent-encoded to handle special characters. 
KVStore :: struct {
    filepath: string,
    mutex: sync.Mutex,
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
    Key_Already_Exists_Error,
    Could_Not_Create_Store_Backup_Error,
    Could_Not_Restore_Original_File_Error
}


@(private="file") KEY_VAL_DELIMITER : string : ":"
@(private="file") ENTRY_DELIMITER : string : ";"

@(private="file") KEY_VAL_DELIMITER_PERCENT_ENCODED : string : "%3A"
@(private="file") ENTRY_DELIMITER_PERCENT_ENCODED : string : "%3B"

// Returns:
// - store: Pointer to the opened File or nil if an error occurred
// - error: If an error occurred during file opening
@(private="file")
get_file :: proc(store: ^KVStore) -> (^os.File, Store_Error) {
    // TODO: maybe hardlock the file with flock (UNIX) or LockFileEx (Windows) to prevent multiple processes from writing to the file at the same time. 
    // This would require a cross-platform implementation of file locking.
    file, err := os.open(store.filepath, flags = os.O_RDWR | os.O_CREATE, perm = os.Permissions_Read_Write_All)
    if err != os.ERROR_NONE {
        return nil, Store_Error.File_Error
    }
    return file, Store_Error.None
}


// build_index reads the data from the file and builds the in-memory index of key-value pairs.
// Returns:
// - error: If an error occurred during indexing, otherwise returns Store_Error.None
@(private="file")
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

// make_store creates a new KVStore instance and initializes it with the data from the file at the specified filepath.

// Returns:
// - store: Pointer to the created KVStore instance or nil if an error occurred
// - error: If an error occurred during store creation or initialization

// Call this once on main thread to create the store. Do not call this on multiple threads.
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

// deallocate frees the memory used by the KVStore instance and its associated data.
deallocate :: proc(store: ^KVStore){

    delete(store.filepath)
    for key, val in store.data{
        delete(key)
        delete(val)
    }
    delete(store.data)
    free(store, context.allocator)
    
}

// key_exists looks up if key exists in database.

// Returns:
// - exists: true if the key exists in the store, false otherwise
key_exists :: proc(store: ^KVStore, key: string) -> bool {
    sync.mutex_lock(&store.mutex)
    defer sync.mutex_unlock(&store.mutex)

    _, ok := store.data[key]
    return ok
}

// read looks up a key in the database file.
//
// If the key is found, it returns a value string 
// cloned from the file buffer. 

// Returns:
// - value: The matching copy of the value string. **The caller is responsible for freeing this 
// - error: If an error occurred during reading a value from the store, otherwise returns Store_Error.None
read :: proc (store: ^KVStore, key: string) -> (string, Store_Error) {
    sync.mutex_lock(&store.mutex)
    defer sync.mutex_unlock(&store.mutex)

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

// Returns:
// - error: If an error occurred during writing to the store, otherwise returns Store_Error.None
write :: proc (store: ^KVStore, key: string, value: string) -> Store_Error {
    sync.mutex_lock(&store.mutex)
    defer sync.mutex_unlock(&store.mutex)

    if _, found := store.data[key]; found { 
        return Store_Error.Key_Already_Exists_Error
    }

    store.data[strings.clone(key)] = strings.clone(value)
    return Store_Error.None

}


// remove removes a key-value pair from the store.

// Returns:
// - error: If an error occurred during removing the key-value pair, otherwise returns Store_Error.None
remove :: proc (store: ^KVStore, key: string) -> Store_Error{
    sync.mutex_lock(&store.mutex)
    defer sync.mutex_unlock(&store.mutex)

    value : string
    found : bool
    if value, found = store.data[key]; !found {
        return Store_Error.Key_Not_Found_Error
    }

    kk, vk := delete_key(&store.data, key)
    delete(kk)
    delete(vk)
    
    return Store_Error.None
}


// Write the updated data in the Store to file

// Returns:
// - error: If an error occurred during syncing the store to file, otherwise returns Store_Error.None
sync :: proc (store: ^KVStore) -> Store_Error {
    sync.mutex_lock(&store.mutex)
    defer sync.mutex_unlock(&store.mutex)
    
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

    
    temp_dir, mkdir_err := os.make_directory_temp(".", "kvstore_sync_temp_dir", context.allocator )
    defer delete(temp_dir)
    defer os.remove(temp_dir)

    if mkdir_err != os.ERROR_NONE{
        fmt.println("Failed to create temporary directory during sync")
        return  Store_Error.Could_Not_Create_Store_Backup_Error
    }
    
    temp, temp_err := os.create_temp_file(temp_dir, "kvstore_sync_temp")
    if temp_err != os.ERROR_NONE{
        os.close(temp)
        fmt.println("Failed to create temporary file during sync")
        return  Store_Error.Could_Not_Create_Store_Backup_Error
    }
    
    bak_path := fmt.aprint(store.filepath, ".bak", sep = "")
    defer delete(bak_path)
    
    copy_err := os.copy_file( bak_path,store.filepath)

    if copy_err != os.ERROR_NONE{
        os.close(temp)
        return  Store_Error.Could_Not_Create_Store_Backup_Error
    }

    _, write_err := os.write_string(temp, strings.to_string(new_lines))
    if write_err != os.ERROR_NONE{
        os.close(temp)
        fmt.println("Failed to write to temporary file during sync")
        return  Store_Error.Sync_Error
    }

    flush_err := os.flush(temp)
    if flush_err != os.ERROR_NONE {
        os.close(temp)
        return Store_Error.Sync_Error
    }


    temp_filepath := strings.clone(os.name(temp))
    defer delete(temp_filepath)
    os.close(temp)
    rename_err := os.rename(temp_filepath, store.filepath)
    if rename_err != os.ERROR_NONE{
        return Store_Error.Sync_Error
    }

    os.remove(bak_path)
    return Store_Error.None

}

// Returns:
// - encoded: The percent-encoded string
percent_encode :: proc(input: string) -> string {
    return net.percent_encode(input)

}

// Returns:
// - decoded: The percent-decoded string
// - ok: If the decoding was successful
percent_decode :: proc(input: string) -> (string, bool) {
    return net.percent_decode(input)
}