package usage

import "core:fmt"
import "core:mem"

import "../../kvstore"

main :: proc (){

    // --------------------------------------------------------------------------------------------
    // Only here for development debugging purposes 

    when ODIN_DEBUG {
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)

        defer {
            if len(track.allocation_map) > 0 {
                fmt.eprintf("=== %v Memory Leaks Detected ===\n", len(track.allocation_map))
                for _, entry in track.allocation_map {
                    fmt.eprintf("- %v bytes leaked @ %v\n", entry.size, entry.location)
                }
            }
            if len(track.bad_free_array) > 0 {
                fmt.eprintf("=== %v Bad Frees Detected ===\n", len(track.bad_free_array))
                for entry in track.bad_free_array {
                    fmt.eprintf("- Bad free @ %v\n", entry.location)
                }
            }
            mem.tracking_allocator_destroy(&track)
        }
	}
    // --------------------------------------------------------------------------------------------

    // KV Store base path can be specified as an argument, otherwise defaults to "."
    store, err := kvstore.make_store("./usagedb")
    if err != nil {
        fmt.println("Failed to create KV store. Error:", err)
        return
    }

    key := ":hello :\""
    value := ";world; "

    // Write an entry to the store
    write_err := kvstore.write(store, key, value)
    if write_err != nil {
        fmt.println("Failed to write to KV store")
    }
    else {
        fmt.println("Successfully wrote key '", key, "' with value '", value, "' to KV store")
    }

    // Read the entry back from the store
    read, read_ok := kvstore.read(store, key)
    defer delete(read, context.allocator)
    if read_ok == nil {
        fmt.println("Retrieved entry for key '", key, "': ", read)
    }
    else {
        fmt.println("Failed to read entry for key '", key, "'")
        return
    }

    // Remove the entry from the store
    del_err := kvstore.remove(store, key)
    if del_err != nil {
        fmt.println("Failed to delete entry")
    }
    else {
        fmt.println("Successfully deleted entry for key '", key, "'")
    }

    // Sync the store to disk 
    sync_err := kvstore.sync(store)
    if sync_err != nil {
        fmt.println("Failed to sync store. Error: ", sync_err)
    }

    // Deallocate the store and free memory 
    kvstore.deallocate(store)


}