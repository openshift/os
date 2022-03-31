package main

import (
	"flag"
	"log"
	"net/http"
)

var (
	// flagPort is the open port the application listens on
	flagPort = flag.String("port", "9091", "Port to listen on")
)

func main() {
	extensions := http.FileServer(http.Dir("/usr/share/rpm-ostree/extensions/"))
	flag.Parse()
	mux := http.NewServeMux()
	mux.Handle("/", extensions)

	log.Printf("listening on port %s", *flagPort)
	log.Fatal(http.ListenAndServe(":"+*flagPort, mux))
}
