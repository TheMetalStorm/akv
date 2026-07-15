# akv

`akv` is an in-memory key-value store backed by a single flat file.

Currently in development, not production ready

## Features
- [x] Concurrent Key-Value Store Library in a single file 
- [x] Usage Example
- [x] Multithreaded Server Example

## TODO
- [x] Implement OS-level file locking (`flock` / `LockFileEx`) to prevent multi-process data corruption.
- [x] Implement atomic file replacement via an interim temporary file swap to protect against crash corruption.
- [ ] Implement support for Windows

## How it works

1. **Initialization:** When `make_store` is called, the library parses the `.db` file and populates an internal Odin map. Keys and values are length-prefix-encoded on disk.
2. **Runtime Operations:** All runtime reads, writes, and deletions interact with the in-memory map. Concurrency is managed via an internal `sync.Mutex`, making operations fully thread-safe.
3. **Memory Ownership:** Because Odin lacks garbage collection, string management is explicit. `read` returns a clone of the value that the caller must free.
4. **Persistence:** Changes are only persisted to disk when you explicitly call `sync()`.

## API Reference

### `make_store(filepath: string) -> (^KVStore, Store_Error)`
Initializes the store from a file path. **Note:** This should only be called once on your main thread during initialization.

### `read(store: ^KVStore, key: string) -> (string, Store_Error)`
Thread-safe read. Returns a cloned copy of the value string. *The caller is responsible for freeing this string.*

### `write(store: ^KVStore, key: string, value: string) -> Store_Error`
Thread-safe insert or update. Returns an error if the key already exists.

### `remove(store: ^KVStore, key: string) -> Store_Error`
Thread-safe deletion of a key and its value from the store.

### `sync(store: ^KVStore) -> Store_Error`
Flushes the in-memory map back to disk.