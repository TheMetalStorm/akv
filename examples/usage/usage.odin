package usage

import "core:fmt"
import "core:mem"

import "../../kvstore"

main :: proc (){
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

    // KV Store name can be specified as an argument, otherwise defaults to "./store.db"
    store, ok := kvstore.make_store()

    key := ":hello :\""
    value := ";world; "

    // Write an entry to the store
    write_ok := kvstore.write(store, key, value)
    if !write_ok {
        fmt.println("Failed to write to KV store")
    }
    else {
        fmt.println("Successfully wrote key '", key, "' with value '", value, "' to KV store")
    }

    // Read the entry back from the store
    entry, entry_ok := kvstore.get_entry(store, key)
    if entry_ok {
        fmt.println("Retrieved entry for key '", key, "': ", entry)
    }

    // Remove the entry from the store
    del_ok := kvstore.remove(store, key)
    if del_ok {
        fmt.println("Deleted entry successfully")
    }

    // Sync the store to disk 
    kvstore.sync(store)

    // Deallocate the store and free memory 
    kvstore.deallocate(store)


}