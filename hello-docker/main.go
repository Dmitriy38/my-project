package main

import (
	"fmt"
	"net/http"

	"github.com/sirupsen/logrus"
)

func handle(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintln(w, "Hello docker Merion Academy!")
}

func main() {
	if err := http.ListenAndServe(":8080", http.HandlerFunc(handle)); err != nil {
		logrus.Error(err)
	}
}
