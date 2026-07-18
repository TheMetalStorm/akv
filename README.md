# akv

`akv` is an in-memory key-value store backed by a single flat file.

Currently in development, not production ready

## Features
- [x] Concurrent Key-Value Store Library in a single file 
- [x] OS-level file locking (`flock`) to prevent multi-process data corruption.
- [x] Atomic file replacement via an interim temporary file swap to protect against crash corruption.
- [x] Usage Example
- [x] Multithreaded Server Example

## May Be Implemented in the Future
- [ ] Support for Windows Platform
- [ ] Storage Access Control
- [ ] Multiple running instances

## Running the Examples

```sh
# Run the usage example
odin run examples/usage

# Run the multithreaded TCP server (requires IP and port args)
odin run examples/kvserver -- 127.0.0.1 8080
```

Connect to the server with `telnet 127.0.0.1 8080` and use commands: `PUT key value`, `GET key`, `DEL key`, `HELP`.

## How it works

1. **Initialization:** When `make_store` is called, the library parses the `.db` file and populates an internal Odin map. Keys and values are length-prefix-encoded on disk.
2. **Runtime Operations:** All runtime reads, writes, and deletions interact with the in-memory map. Concurrency is managed via an internal `sync.Mutex`, making operations fully thread-safe.
3. **Memory Ownership:** Because Odin lacks garbage collection, string management is explicit. `read` returns a clone of the value that the caller must free.
4. **Persistence:** Changes are only persisted to disk when you explicitly call `sync()`.


## Usage

```odin
package main

import "core:fmt"
import "kvstore"

main :: proc() {
    store, err := kvstore.make_store("./mydb")
    if err != nil {
        fmt.println("Failed to create KV store:", err)
        return
    }
    defer kvstore.deallocate(store)

    kvstore.write(store, "hello", "world")
    kvstore.write(store, "foo", "bar")

    if value, value_err := kvstore.read(store, "hello"); value_err == nil {
        defer delete(value)
        fmt.println("hello =", value)
    }

    if kvstore.key_exists(store, "foo") {
        kvstore.remove(store, "foo")
    }

    kvstore.sync(store)
}
```

## API Reference

All functions return `Store_Error`, a `#shared_nil` union:

```odin
Store_Error :: union #shared_nil {
    os.Error,                  // filesystem/IO/platform errors
    runtime.Allocator_Error,   // memory allocation errors
    Parse_Error,               // index decoding errors
    Key_Error,                 // key conflicts/not found
    Init_Error,                // invalid config
}
```

Callers check `if err != nil` and can type-switch on the union variant for specific handling.

### `make_store(base_path:= ".", allocator := context.allocator) -> (^KVStore, Store_Error)`
Initializes the store in the given base path. **Note:** This should only be called once on your main thread during initialization.

### `read(store: ^KVStore, key: string) -> (string, Store_Error)`
Thread-safe read. Returns a cloned copy of the value string. *The caller is responsible for freeing this string.* Returns `Key_Error.Key_Not_Found` if absent.

### `write(store: ^KVStore, key: string, value: string) -> Store_Error`
Thread-safe insert. Returns `Key_Error.Key_Already_Exists` if the key already exists.

### `remove(store: ^KVStore, key: string) -> Store_Error`
Thread-safe deletion of a key and its value from the store. Returns `Key_Error.Key_Not_Found` if absent.

### `sync(store: ^KVStore) -> Store_Error`
Flushes the in-memory map back to disk.

### `key_exists(store: ^KVStore, key: string) -> bool`
Thread-safe check if a key exists in the store.

### `deallocate(store: ^KVStore)`
Frees all memory used by the store. Must be called when done.