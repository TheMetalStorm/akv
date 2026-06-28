package kvstore

import "core:path/filepath"
import "core:fmt"
import "core:os"


// stored in file as "key1:value1;key2:value2"
KVStore :: struct {
    file: ^os.File
    // TODO: cache
    // TODO: compress and decompress data?
    // TODO: make thread safe
}

init :: proc(filepath: string) -> (KVStore, bool) {
    file, err := os.create(filepath)
    if err != os.ERROR_NONE {
        fmt.println("Could not create file for KV Store \n Error: %v", err)
        return KVStore{}, false
    }

    store: KVStore = KVStore{file}

    return store, true
}

write :: proc (store: ^KVStore, key: string, value: string)  {
    // Check if key exist
    // if yes, notify user
    // if not, put!
    //   seek to end of file length and just write
}

read :: proc (store: ^KVStore, key: string) -> (string, bool) {
    // Check if key exist
    // if yes, notify user
    // if not, return value
    //   split by line, then every line by : and check if correct key
    return "", false
}