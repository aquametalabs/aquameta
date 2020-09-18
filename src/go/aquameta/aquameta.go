package main

import (
    "io"
    "context"
    "fmt"
    "os"
    "log"
    "net/http"
    "strings"

    "github.com/jackc/pgx/v4/pgxpool"
)

func main() {
    //
    // initial stuff?  cmd args and the like.
    //

    fmt.Println("Aquameta daemon... ENGAGE!")



    //
    // connect to database
    //

    // In any case, statement caching can be disabled by connecting with statement_cache_capacity=0.
    dbpool, err := pgxpool.Connect(context.Background(), os.Getenv("DATABASE_URL"))
    if err != nil {
        fmt.Fprintf(os.Stderr, "Unable to connect to database: %v\n", err)
        os.Exit(1)
    }
    defer dbpool.Close()


    //
    // request handlers
    //


    // event

    eventHandler := func(w http.ResponseWriter, req *http.Request) {
        io.WriteString(w, "Hello from eventHandler!\n" + req.Method + "\n")
    }


    // endpoint

    apiHandler := func(w http.ResponseWriter, req *http.Request) {
        io.WriteString(w, "Hello from the REST API.  Here are some stats:\n")
        io.WriteString(w, "RequestURI: "+req.RequestURI+"\n")
        io.WriteString(w, "Proto: "+req.Proto+"\n\n\n")

        // result strings
        var message string
        var response string
        var mimetype string

        err = dbpool.QueryRow(context.Background(),
            "select message, response, mimetype from endpoint.request('0.2', '" + req.Method + "', '" +
            strings.TrimPrefix(req.RequestURI,"/endpoint/0.2/") + "','{}'::json,'{}'::json)").Scan(&message, &response, &mimetype)

        if err != nil {
            fmt.Fprintf(os.Stderr, "QueryRow failed: %v\n", err)
            os.Exit(1)
        }
        io.WriteString(w, "message: "+message+"\n")
        io.WriteString(w, "mimetype: "+mimetype+"\n")
        io.WriteString(w, "response: "+response+"\n")

    }

    http.HandleFunc("/endpoint/", apiHandler)
    http.HandleFunc("/event/", eventHandler)


    //
    // start http server
    //

    log.Fatal(http.ListenAndServe(":9000", nil))
}
