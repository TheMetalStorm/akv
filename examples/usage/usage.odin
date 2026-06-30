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

    write_ok := kvstore.write(store, "hello", "world")
    if !write_ok {
        fmt.println("Failed to write to KV store")
    }
    else {
        fmt.println("Successfully wrote key 'hello' with value 'world' to KV store")
    }

    entry, entry_ok := kvstore.get_entry(store, "hello")
    if entry_ok {
        fmt.println("Retrieved entry:", entry)
    }


    del_ok := kvstore.del(store, "hello")
    if del_ok {
        fmt.println("Deleted entry successfully")
    }

    // Sync the store to disk 
    kvstore.sync(store)

    // Deallocate the store and free memory (currently doesn not free values strings)
    kvstore.deallocate(store)


}