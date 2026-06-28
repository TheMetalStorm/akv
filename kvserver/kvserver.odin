package kvserver
import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"
import "core:thread"
import "../kvstore"
main :: proc() {

    endpoint, ok := parse_args()
    
    if !ok {
        fmt.println("Failed to parse Command Line Args")
        os.exit(1)
    }

	start_server(endpoint)
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


handle_msg_echo :: proc(sock: net.TCP_Socket) {
	buffer: [256]u8
	for {
		bytes_recv, err_recv := net.recv_tcp(sock, buffer[:])
		if err_recv != nil {
			fmt.println("Failed to receive data")
		}
		received := buffer[:bytes_recv]
		if len(received) == 0 ||
		   is_ctrl_d(received) ||
		   is_empty(received) ||
		   is_telnet_ctrl_c(received) {
			fmt.println("Disconnecting client")
			break
		}
		fmt.printfln("Server received [ %d bytes ]: %s", len(received), received)
		bytes_sent, err_send := net.send_tcp(sock, received)
		if err_send != nil {
			fmt.println("Failed to send data")
		}
		sent := received[:bytes_sent]
		fmt.printfln("Server sent [ %d bytes ]: %s", len(sent), sent)
	}
	net.close(sock)
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

start_server :: proc(endpoint: net.Endpoint){
  
	sock, err := net.listen_tcp(endpoint)
	if err != nil {
		fmt.println("Failed to listen on TCP")
		return
	}

	kvstore.init("./store.data")

    fmt.printfln("Listening on TCP: %s", net.endpoint_to_string(endpoint))
    	for {
		cli, _, err_accept := net.accept_tcp(sock)
		if err_accept != nil {
			fmt.println("Failed to accept TCP connection")
			continue
		}
		handle_msg_echo(cli)
		//TODO: multithreaded
		//thread.create_and_start_with_poly_data(cli, handle_msg_echo)
	}
	net.close(sock)
	fmt.println("Closed socket")

}