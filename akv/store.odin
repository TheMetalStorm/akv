package akv

import "core:strconv"
import "core:os"
import "core:strings"
import "base:runtime"
import "core:sync"
import "core:sys/posix"

// Currently only a Unix implementation is provided, but it should be easy to add a Windows implementation if needed.
// NOTE: We use length-prefixed encoding to store the data in the format "len(data):data"
// EXAMPLE: 5:hello5:world

KVStore :: struct {
    base_path: string,
    mutex: sync.Mutex,
    data: map[string]string
}


Store_Error :: union #shared_nil {
    os.Error,
    runtime.Allocator_Error,
    Parse_Error,
    Key_Error,
    Init_Error,
}

Parse_Error :: enum {
    None = 0,
    Decoding,
    Decoding_Missing_Length,
    Decoding_Missing_Colon,
    Decoding_Abrupt_End_Of_Data,
    Truncated_Entry,
    Indexing,
    Parsing,
}

Key_Error :: enum {
    None = 0,
    Key_Not_Found,
    Key_Already_Exists,
}

Init_Error :: enum {
    None = 0,
    Empty_Base_Path,
    Base_Path_Points_At_File,
}

@(private="file") STORE_NAME : string : "data.db"
@(private="file") STORE_LOCK_NAME : string : "data.db.lock"
@(private="file") STORE_BAK_NAME : string : "data.db.bak"

@(private="file") LEN_DELIMITER : string : ":"


@(private="file")
parse_length_encoded_string :: proc (data_str: string,  data_ptr: ^int)  -> (res: string, err: Store_Error) {
    len_num: int
    num, parsed := strconv.parse_int(data_str[data_ptr^:],  n = &len_num)
    if (num == 0 && len_num == 0 && !parsed){
        return "", Parse_Error.Decoding_Missing_Length
    }
    
    if data_ptr^+len_num >= len(data_str) {
        return "", Parse_Error.Truncated_Entry    
    }

    data_ptr^ += len_num 
    
    if data_str[data_ptr^] != ':' {
        return "", Parse_Error.Decoding_Missing_Colon
    }
    
    data_ptr^ += 1
    if data_ptr^+num > len(data_str) {
        return "", Parse_Error.Decoding_Abrupt_End_Of_Data    }
    ret := strings.clone(data_str[data_ptr^:data_ptr^ + num])

    data_ptr^ += num
    return ret, nil
}

// build_index reads the data from the file and builds the in-memory index of key-value pairs.
// Returns:
// - error: If an error occurred during indexing, otherwise returns nil
@(private="file")
build_index :: proc(store: ^KVStore) -> Store_Error {

    lock_file_path, lock_file_err := os.join_path({store.base_path, STORE_LOCK_NAME}, context.allocator)
    if lock_file_err != runtime.Allocator_Error.None {
        return lock_file_err
    }
    defer delete(lock_file_path)

    cstr := strings.clone_to_cstring(lock_file_path)
    defer delete(cstr)
    
    fd := posix.open(cstr, posix.O_Flags{.RDWR, .CREAT}, {.IRUSR, .IWUSR, .IRGRP, .IROTH})
    if fd == -1 {
        return os.Error(os.Platform_Error(i32(posix.errno())))
    }
    defer posix.close(fd)

    lock: posix.flock
	lock.l_type = posix.Lock_Type.WRLCK
	lock.l_whence = posix.SEEK_SET
    lock.l_start = 0
	lock.l_len = 0
    res := posix.fcntl(fd, posix.FCNTL_Cmd.SETLKW, &lock)
    if res == -1 {
        return os.Error(os.Platform_Error(i32(posix.errno())))
    }

    defer {
        unlock: posix.flock
        unlock.l_type = posix.Lock_Type.UNLCK
        unlock.l_whence = posix.SEEK_SET
        unlock.l_start = 0
        unlock.l_len = 0
        posix.fcntl(fd, posix.FCNTL_Cmd.SETLK, &unlock)
    }

    store_file_path, store_file_err := os.join_path({store.base_path, STORE_NAME}, context.allocator)
    if store_file_err != runtime.Allocator_Error.None {
        return store_file_err
    }
    defer delete(store_file_path)

    if !os.exists(store_file_path){
        f, create_err := os.create(store_file_path)
        if create_err != os.ERROR_NONE {
            return create_err
        }
        os.close(f)
    }
    data, read_err := os.read_entire_file(store_file_path, context.allocator)
    if read_err != os.ERROR_NONE{
        return read_err
    }
    defer delete(data)

    data_str := strings.clone_from_bytes(data)
    defer delete(data_str)

    data_ptr : int = 0

    for(data_ptr < len(data_str)){

        key, key_err := parse_length_encoded_string(data_str, &data_ptr)
        if key_err != nil do return key_err
        val, val_err := parse_length_encoded_string(data_str, &data_ptr)
        if val_err != nil do return val_err
 
        store.data[key] = val
    }

    return nil
}

// make_store creates a new KVStore instance and initializes it with the data from the file at the specified filepath.

// Returns:
// - store: Pointer to the created KVStore instance or nil if an error occurred
// - error: If an error occurred during store creation or initialization

// Call this once on main thread to create the store. Do not call this on multiple threads.
make_store :: proc(base_path:= ".", allocator := context.allocator) -> (^KVStore, Store_Error) {
    store, alloc_err := new(KVStore, allocator)
    if alloc_err != runtime.Allocator_Error.None do return nil, alloc_err


    if strings.trim_space(base_path) == ""{
        return nil, Init_Error.Empty_Base_Path
    }

    if !os.is_directory(base_path){
        if os.is_file(base_path){
            return nil, Init_Error.Base_Path_Points_At_File
        }
        mkdir_err := os.make_directory_all(base_path)
        if mkdir_err != os.ERROR_NONE {
            return nil, mkdir_err
        }
    }

    store.base_path = strings.clone(base_path, allocator)
    store.data = {} 

    store_err := build_index(store)
    if store_err != nil {
        deallocate(store)
        return nil, store_err
    }

    return store, nil
}

// deallocate frees the memory used by the KVStore instance and its associated data.
deallocate :: proc(store: ^KVStore){

    delete(store.base_path)
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
// - error: If an error occurred during reading a value from the store, otherwise returns nil
read :: proc (store: ^KVStore, key: string) -> (string, Store_Error) {
    sync.mutex_lock(&store.mutex)
    defer sync.mutex_unlock(&store.mutex)

    value, ok := store.data[key]
    if ok{
        return strings.clone(value), nil
    }
    return "", Key_Error.Key_Not_Found

}

// write inserts a key-value pair into the store.
//
// The key and value are copied into the store.
// The caller retains ownership of the original strings.

// Returns:
// - error: If an error occurred during writing to the store, otherwise returns nil
write :: proc (store: ^KVStore, key: string, value: string) -> Store_Error {
    sync.mutex_lock(&store.mutex)
    defer sync.mutex_unlock(&store.mutex)

    if _, found := store.data[key]; found { 
        return Key_Error.Key_Already_Exists
    }

    store.data[strings.clone(key)] = strings.clone(value)
    return nil

}


// remove removes a key-value pair from the store.

// Returns:
// - error: If an error occurred during removing the key-value pair, otherwise returns nil
remove :: proc (store: ^KVStore, key: string) -> Store_Error{
    sync.mutex_lock(&store.mutex)
    defer sync.mutex_unlock(&store.mutex)

    value : string
    found : bool
    if value, found = store.data[key]; !found {
        return Key_Error.Key_Not_Found
    }

    kk, vk := delete_key(&store.data, key)
    delete(kk)
    delete(vk)
    
    return nil
}


// Write the updated data in the Store to file

// Returns:
// - error: If an error occurred during syncing the store to file, otherwise returns nil
sync :: proc (store: ^KVStore) -> Store_Error {
    sync.mutex_lock(&store.mutex)
    defer sync.mutex_unlock(&store.mutex)
    
    lock_file_path, err := os.join_path({store.base_path, STORE_LOCK_NAME}, context.allocator)
    if err != runtime.Allocator_Error.None {
        return err
    }
    defer delete(lock_file_path)

    cstr := strings.clone_to_cstring(lock_file_path)
    defer delete(cstr)
    
    fd := posix.open(cstr, posix.O_Flags{.RDWR, .CREAT}, {.IRUSR, .IWUSR, .IRGRP, .IROTH})
    if fd == -1 {
        return os.Error(os.Platform_Error(i32(posix.errno())))
    }
    defer posix.close(fd)
    
    lock: posix.flock
	lock.l_type = posix.Lock_Type.WRLCK
	lock.l_whence = posix.SEEK_SET
    lock.l_start = 0
	lock.l_len = 0
    res := posix.fcntl(fd, posix.FCNTL_Cmd.SETLKW, &lock)
    if res == -1 {
        return os.Error(os.Platform_Error(i32(posix.errno())))
    }

    defer {
        unlock: posix.flock
        unlock.l_type = posix.Lock_Type.UNLCK
        unlock.l_whence = posix.SEEK_SET
        unlock.l_start = 0
        unlock.l_len = 0
        posix.fcntl(fd, posix.FCNTL_Cmd.SETLK, &unlock)
    }

    new_lines := strings.builder_make_none()
    defer strings.builder_destroy(&new_lines)

    for key, val in store.data {
        strings.write_int(&new_lines, (len(key)))
        strings.write_string(&new_lines, LEN_DELIMITER)
        strings.write_string(&new_lines, key)
        strings.write_int(&new_lines, len(val))
        strings.write_string(&new_lines, LEN_DELIMITER)
        strings.write_string(&new_lines, val)
    }

    
    temp_dir, mkdir_err := os.make_directory_temp(store.base_path, "akv_sync_temp_dir", context.allocator )

    defer delete(temp_dir)
    defer os.remove(temp_dir)

    if mkdir_err != os.ERROR_NONE{
        return  mkdir_err
    }
    
    temp, temp_err := os.create_temp_file(temp_dir, "akv_sync_temp")
    if temp_err != os.ERROR_NONE{
        return  temp_err
    }

    bak_file_path, bak_err := os.join_path({store.base_path, STORE_BAK_NAME}, context.allocator)
    if bak_err != runtime.Allocator_Error.None {
        return bak_err
    }
    defer delete(bak_file_path)
    
    file_path, file_path_err := os.join_path({store.base_path, STORE_NAME},context.allocator)
    if file_path_err != runtime.Allocator_Error.None {
        return file_path_err
    }
    defer delete(file_path)

    copy_err := os.copy_file(bak_file_path, file_path)

    if copy_err != os.ERROR_NONE{
        os.close(temp)
        return  copy_err
    }

    _, write_err := os.write_string(temp, strings.to_string(new_lines))
    if write_err != os.ERROR_NONE{
        os.close(temp)
        return  write_err
    }

     
    sync_err := os.sync(temp)
    if sync_err != os.ERROR_NONE {
        os.close(temp)
        return sync_err
    }


    temp_filepath := strings.clone(os.name(temp))
    defer delete(temp_filepath)
    os.close(temp)
    rename_err := os.rename(temp_filepath, file_path)
    if rename_err != os.ERROR_NONE{
        return rename_err
    }

    os.remove(bak_file_path)

    data_folder, folder_err := os.open(get_data_folder_path(store), flags = os.O_RDONLY )
    if folder_err != os.ERROR_NONE {
        return folder_err
    }
    defer os.close(data_folder)

    sync_err = os.sync(data_folder)
    if sync_err != os.ERROR_NONE {
        return sync_err
    }
    return nil
}

// TODO: Directory Permissions (0700) so that we control who can access data folder
@(private="file")
get_data_folder_path :: proc( store: ^KVStore) -> string{
    return store.base_path
}