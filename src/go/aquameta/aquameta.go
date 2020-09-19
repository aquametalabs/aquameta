package main

import (
    "io"
    "context"
    "fmt"
    "os"
    "log"
    "net/http"
    "strings"

    "github.com/lib/pq"
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
    // authenticate
    //


    //
    // request handlers
    //


    // endpoint handler

    apiHandler := func(w http.ResponseWriter, req *http.Request) {
        // request strings
        full_path := strings.SplitN(req.RequestURI,"?", 2)[0]
        s := strings.SplitN(full_path,"/",4)
        version, path := s[2], s[3]

        // result strings
        var status int
        var message string
        var mimetype string
        var response string

        // query endpoint.request()
        err = dbpool.QueryRow(
            context.Background(),
            fmt.Sprintf(
                "select status, message, response, mimetype from endpoint.request(%v, %v, %v, '{}'::json,'{}'::json)",
                pq.QuoteLiteral(version),
                pq.QuoteLiteral(req.Method),
                pq.QuoteLiteral(path))).Scan(
                    &status, &message, &response, &mimetype)

        if err != nil {
            fmt.Fprintf(os.Stderr, "QueryRow failed: %v\n", err)
            os.Exit(1)
        }

        // set mimetype
        w.Header().Set("Content-Type", mimetype)

        /*
        // url parts
        io.WriteString(w, "Hello from the REST API.  Here are some stats:\n")
        io.WriteString(w, "RequestURI: "+req.RequestURI+"\n")
        io.WriteString(w, "full_path: "+full_path+"\n")
        io.WriteString(w, "version: "+version+"\n")
        io.WriteString(w, "path: "+path+"\n")
        io.WriteString(w, "Proto: "+req.Proto+"\n\n\n")

        io.WriteString(w, "status: "+message+"\n")
        io.WriteString(w, "message: "+message+"\n")
        io.WriteString(w, "mimetype: "+mimetype+"\n")
        io.WriteString(w, "response: "+response+"\n")
        */

        // response body
        io.WriteString(w, response)
    }


    // resource handler

    resourceHandler := func(w http.ResponseWriter, req *http.Request) {
        io.WriteString(w, "Hello from resourceHandler!\n" + req.Method + "\n")
    }


    // events handler

    eventHandler := func(w http.ResponseWriter, req *http.Request) {
        io.WriteString(w, "Hello from eventHandler!\n" + req.Method + "\n")
    }


    //
    // attach handlers
    //

    http.HandleFunc("/endpoint/", apiHandler)
    http.HandleFunc("/event/", eventHandler)
    http.HandleFunc("/", resourceHandler)


    //
    // start http server
    //

    log.Fatal(http.ListenAndServe(":9000", nil))
}
