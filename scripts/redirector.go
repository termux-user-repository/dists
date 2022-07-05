package main

import (
	"fmt"
	"log"
	"net/http"
	"regexp"
	"strings"
)

func ModifyName(n string) string {
	reg, err := regexp.Compile("[^a-zA-Z0-9-_+]+")
	if err != nil {
		log.Fatal(err)
	}
	processedString := reg.ReplaceAllString(n, ".")
	return processedString
}
func Dists_tur(w http.ResponseWriter, r *http.Request) {
	uri := r.URL.Path
	redirect_to := "https://termux-user-repository.github.io"
	new_url := redirect_to + uri
	http.Redirect(w, r, new_url, 302)

}
func pool_tur(w http.ResponseWriter, r *http.Request) {
	uri := r.URL.Path
	arr_uri := strings.Split(uri, "/")
	deb_name := ModifyName(arr_uri[len(arr_uri)-1])
	redirect_to := "https://github.com/termux-user-repository/dists/releases/download/0.1/"

	new_url := redirect_to + deb_name
	http.Redirect(w, r, new_url, 302)

}
func Dists(w http.ResponseWriter, r *http.Request) {
	uri := r.URL.Path
	//arr_uri := strings.Split(uri,"/")
	//deb_name := ModifyName(arr_uri[len(arr_uri)-1])
	redirect_to := "https://termux-pod.github.io/apt"

	new_url := redirect_to + uri
	http.Redirect(w, r, new_url, 302)
}
func Handler(w http.ResponseWriter, r *http.Request) {
	uri := r.URL.Path
	arr_uri := strings.Split(uri, "/")
	deb_name := ModifyName(arr_uri[len(arr_uri)-1])
	var redirect_to string
	pkg := arr_uri[1]
	games := "https://github.com/Termux-pod/game-packages/releases/download/deb/"
	main := "https://github.com/Termux-pod/termux-packages/releases/download/debfile/"
	root := "https://github.com/Termux-pod/termux-root-packages/releases/download/deb/"
	science := "https://github.com/Termux-pod/science-packages/releases/download/deb/"
	unstable := "https://github.com/Termux-pod/unstable-packages/releases/download/deb/"
	x11 := "https://github.com/Termux-pod/x11-packages/releases/download/deb/"
	switch pkg {
	case "termux-games":
		redirect_to = games
	case "termux-main":
		redirect_to = main
	case "termux-root":
		redirect_to = root
	case "termux-science":
		redirect_to = science
	case "termux-unstable":
		redirect_to = unstable
	case "termux-x11":
		redirect_to = x11
	default:
		w.WriteHeader(http.StatusOK)
		w.Header().Set("Content-Type", "application/text")
		w.Write([]byte("Success yeah\n"))
		return
	}
	new_url := redirect_to + deb_name
	http.Redirect(w, r, new_url, 302)
	fmt.Printf(deb_name)
	fmt.Printf(new_url)
}

func rootHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Header().Set("Content-Type", "application/text")
	w.Write([]byte("Okay: This page is not supposed to be in browser:::"))
	return
}

func main() {
	http.HandleFunc("/termux-games/dists/", Dists)
	http.HandleFunc("/termux-main/dists/", Dists)
	http.HandleFunc("/termux-science/dists/", Dists)
	http.HandleFunc("/termux-root/dists/", Dists)
	http.HandleFunc("/termux-unstable/dists/", Dists)
	http.HandleFunc("/termux-x11/dists/", Dists)
	http.HandleFunc("/dists/", Dists_tur)
	http.HandleFunc("/pool/", pool_tur)
	http.HandleFunc("/", Handler)
	fmt.Printf("Starting server at port 8091\n")
	if err := http.ListenAndServe("localhost:8091", nil); err != nil {
		log.Fatal(err)
	}
}
