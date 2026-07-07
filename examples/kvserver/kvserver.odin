package kvserver
import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"
import "base:runtime"
import "core:mem"
import "core:thread"

import "../../kvstore"

KVServer :: struct{
	store: ^kvstore.KVStore,
	endpoint: net.Endpoint
}

FALSE_COMMAND_MESSAGE : string : "The command is invalid!\nPlease use the HELP command to see the list of valid commands\n"
KEY_NOT_FOUND_MESSAGE : string : "Key not found in store!\n"

SYNC_SUCCESS_MESSAGE : string : "Synced Store sucessfully!"

DEL_SUCCESS_MESSAGE : string : "Deleted Key sucessfully!\n"
DEL_TOO_MANY_MESSAGE : string : "DEL expects one argument. Refer to the HELP command for more information\n"

GET_TOO_MANY_MESSAGE : string : "GET expects one argument. Refer to the HELP command for more information\n"

HELP_MESSAGE : string : "Commands:\n" +
	"PUT key value - Store a key-value pair in the KV Store. Key is not allowed to contain spaces\n" +
	"GET key - Retrieve the value associated with a key from the KV Store\n" +
	"DEL key - Delete a key-value pair from the KV Store\n" +
	"HELP - Display this help message\n"

main :: proc() {
    track: mem.Tracking_Allocator
    
    when ODIN_DEBUG {
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)
    }

    defer when ODIN_DEBUG {
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

	server, server_ok := init_server()
	defer deallocate(&server)
	if !server_ok{
		fmt.println("Could not create KV Store, shutting down")
		os.exit(1)
	} 
	start(&server)
}

deallocate :: proc(server: ^KVServer)  {
	kvstore.deallocate(server.store)
}

init_server :: proc() -> (KVServer, bool) {

	store, store_err := kvstore.make_store()
	if store_err != kvstore.Store_Error.None {
		fmt.println("Could not create KV Store, shutting down. Error:", store_err)
		return {}, false
	}

	endpoint, endpoint_ok := parse_args()
    
    if !endpoint_ok {
        fmt.println("Failed to parse Command Line Args")
        return {}, false
    }
	return KVServer{store, endpoint}, true
}



is_ctrl_d :: proc(bytes: []u8) -> bool {
	return len(bytes) == 1 && bytes[0] == 4
}

is_empty :: proc(bytes: []u8) -> bool {
	return(
		(len(bytes) == 2 && bytes[0] == '\r' && bytes[1] == '\n') ||
		(len(bytes) == 1 && bytes[0] == '\n') \
	)
}

is_telnet_ctrl_c :: proc(bytes: []u8) -> bool {
	return(
		(len(bytes) == 3 && bytes[0] == 255 && bytes[1] == 251 && bytes[2] == 6) ||
		(len(bytes) == 5 &&
				bytes[0] == 255 &&
				bytes[1] == 244 &&
				bytes[2] == 255 &&
				bytes[3] == 253 &&
				bytes[4] == 6) \
	)
}

handle_command :: proc(server: ^KVServer, sock: net.TCP_Socket){
	buffer: [256]u8
	for {
		bytes_recv, err_recv := net.recv_tcp(sock, buffer[:])
		if err_recv != nil {
			fmt.println("Failed to receive data")
		}
		received := buffer[:bytes_recv] 

		if len(received) == 0 ||
		   is_ctrl_d(received) ||
		   is_telnet_ctrl_c(received) {
			fmt.println("Disconnecting client")
			break
		}

		command := string(received)

		// //First we check for help message
		help_command_split, err_help := strings.split(command, " ")
		defer delete(help_command_split)
		if err_help != runtime.Allocator_Error.None {
			fmt.println("Command is invalid")
			fmt.println("Error:", err_help)
			send(sock, FALSE_COMMAND_MESSAGE)
			continue
		}
		fmt.printfln("Server received command: %s", command)

		t := strings.trim_space(help_command_split[0])

		if len(help_command_split) == 1 && t == "HELP" {
			fmt.printfln("Server received HELP command: %s", command)
			send(sock, HELP_MESSAGE)
			continue
		}

		command_split, err := strings.split_n(command, " ", 2)
		defer delete(command_split)
		if err != runtime.Allocator_Error.None {
			fmt.println("Command is invalid")
			fmt.println("Error:", err)
			send(sock, FALSE_COMMAND_MESSAGE)
			continue
		}
		
		switch command_split[0]{
			case "DEL":
				del_key, err := strings.split(command_split[1], " ")
				defer delete(del_key)

				if err != runtime.Allocator_Error.None {
					fmt.println("Command is invalid")
					fmt.println("Error:", err)
					send(sock, FALSE_COMMAND_MESSAGE)
					continue
				}
				
				if len(del_key) == 1 {
					trimmed  := strings.trim_space(del_key[0])
		
					remove_err := kvstore.remove(server.store, trimmed)

					if remove_err == kvstore.Store_Error.None {
						sync_err := kvstore.sync(server.store)

						if sync_err != kvstore.Store_Error.None {
							fmt.println("Failed to sync store after deleting key:", trimmed)
							send(sock, "Failed to sync store!\n")
						}
						fmt.println("Deleted key:", trimmed)
						send(sock, DEL_SUCCESS_MESSAGE)
					} else {
						fmt.println("Key not found:", trimmed)
						send(sock, KEY_NOT_FOUND_MESSAGE)
					}
				}
				else {
					fmt.println("Command is invalid")
					send(sock, FALSE_COMMAND_MESSAGE)
					send(sock, DEL_TOO_MANY_MESSAGE)
				}

			case "GET":
				get_key, err := strings.split_n(command_split[1], " ", 2)
				defer delete(get_key)

				if err != runtime.Allocator_Error.None {
					fmt.println("Command is invalid")
					fmt.println("Error:", err)
					send(sock, FALSE_COMMAND_MESSAGE)
					continue
				}
				
				if len(get_key) == 1 {
					trimmed  := strings.trim_space(get_key[0])

					value, err := kvstore.read(server.store, trimmed)
					defer delete(value, context.allocator)
					if err == kvstore.Store_Error.None {
						fmt.println("Retrieved value for key:", trimmed, "value:", value)
						send(sock, value)
						send(sock, "\n")
					} else {
						fmt.println("Key not found:", trimmed, "Error:", err)
						send(sock, KEY_NOT_FOUND_MESSAGE)
					}
				}
				else {
					fmt.println("Command is invalid")
					send(sock, FALSE_COMMAND_MESSAGE)
					send(sock, GET_TOO_MANY_MESSAGE)
				}
			
			// NOTE: Key is not allowed to contain spaces. The library can handle keys with spaces, but the server does not support it at this time.
			case "PUT":
				put_key_val, err := strings.split_n(command_split[1], " ", 2)
				defer delete(put_key_val)

				if err != runtime.Allocator_Error.None {
					fmt.println("Command is invalid")
					fmt.println("Error:", err)
					send(sock, FALSE_COMMAND_MESSAGE)
					continue
				}
				if len(put_key_val) == 2 {
					trimmed_key  := strings.trim_space(put_key_val[0])
					trimmed_val  := strings.trim_space(put_key_val[1])

					if kvstore.key_exists(server.store, trimmed_key){
						fmt.println("Key already exists in store:", trimmed_key)
						send(sock, "Key already exists in store!\n")
						continue
					}

					write_err := kvstore.write(server.store, trimmed_key, trimmed_val)
					if write_err != kvstore.Store_Error.None {
						fmt.println("Failed to write key-value pair:", trimmed_key, trimmed_val)
						send(sock, "Failed to write key-value pair!\n")
					}
					else {
						sync_err := kvstore.sync(server.store)
						if sync_err != kvstore.Store_Error.None {
							fmt.println("Failed to sync store after writing key-value pair:", trimmed_key, trimmed_val)
							send(sock, "Failed to sync store!\n")
						}
						fmt.println("Wrote key-value pair:", trimmed_key, trimmed_val)
						send(sock, "Wrote key-value pair successfully!\n")
					}
				} else {
					fmt.println("Command is invalid")
					send(sock, FALSE_COMMAND_MESSAGE)
				}
			case :
				fmt.println("Command is invalid")
				send(sock, FALSE_COMMAND_MESSAGE)
		}
	}
	net.close(sock)
}

send :: proc (sock: net.TCP_Socket, message: string){
	bytes_sent, err_send := net.send_tcp(sock, transmute([]byte)message)
	if err_send != nil {
		fmt.println("Failed to send data:", message)
	}
}

parse_args :: proc() -> (net.Endpoint, bool) {
    addr, addr_ok := net.parse_ip4_address(os.args[1]); 
    if !addr_ok{
		fmt.println("Failed to parse IP address")
		return net.Endpoint{}, false
	}
	
    port, port_ok := strconv.parse_int(os.args[2]); 
    if !port_ok {
		fmt.println("Failed to parse Port")
		return net.Endpoint{}, false

	}

    return net.Endpoint {
		address = addr,
		port    = port,
	}, true
}

start :: proc(server: ^KVServer){
  
	sock, err := net.listen_tcp(server.endpoint)
	if err != nil {
		fmt.println("Failed to listen on TCP")
		return
	}

    fmt.printfln("Listening on TCP: %s", net.endpoint_to_string(server.endpoint))
    	for {
			cli, _, err_accept := net.accept_tcp(sock)
			if err_accept != nil {
				fmt.println("Failed to accept TCP connection")
				continue
			}
			// WITHOUT MULTITHREADING, THIS WILL BLOCK THE SERVER FROM ACCEPTING NEW CONNECTIONS UNTIL THE CLIENT DISCONNECTS
			//handle_command(server, cli)
			// WITH MULTITHREADING, THE SERVER CAN ACCEPT NEW CONNECTIONS WHILE HANDLING CLIENT COMMANDS
			thread.create_and_start_with_poly_data2(server, cli, handle_command)
	}
	net.close(sock)
	fmt.println("Closed socket")

}