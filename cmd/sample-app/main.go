package main

import (
	"fmt"
	"net/http"
)

var sink [][]byte

func hello(w http.ResponseWriter, _ *http.Request) {
	_, err := fmt.Fprintf(w, "Hello from web")
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}

func oom(w http.ResponseWriter, _ *http.Request) {
	for {
		b := make([]byte, 10*1024*1024)
		sink = append(sink, b)

		fmt.Fprintf(w, "allocated %d chunks\n", len(sink))
	}
}

func main() {
	http.HandleFunc("/hello", hello)
	http.HandleFunc("/leak", oom)

	err := http.ListenAndServe(":8080", nil)
	if err != nil {
		fmt.Println("Quitting ...")
		return
	}
}
