package main

import (
    "io"
    "io/ioutil"
    "context"
    "fmt"
    "os"
    "log"
    "net/http"
    "net/url"
    "strings"
    "encoding/json"

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

    // TODO


    //
    // request handlers
    //


    // endpoint handler

    apiHandler := func(w http.ResponseWriter, req *http.Request) {
        // api version, sub-path
        s := strings.SplitN(req.URL.Path,"/",4)
        version, apiPath := s[2], s[3]

        // convert query string to JSON
        m, err := url.ParseQuery(req.URL.RawQuery)
        if err != nil { log.Fatal(err) }
        q, err := json.Marshal(m)
        if err != nil { log.Fatal(err) }
        queryStringJSON := string(q)
        if queryStringJSON == "" { queryStringJSON = "{}" }
        // qsJSON := strings.ReplaceAll(string(js), ",", ", ")

        /*
        // convert req.Header JSON
        headerJSON, err := json.Marshal(req.Header)
        if err != nil { log.Fatal(err) }
        log.Println(string(headerJSON))

        // convert req.Header to bytes
        headerBytes := bytes.Buffer{}
        req.Header.Write(&headerBytes)
        */


        // read request body
        r, err := ioutil.ReadAll(req.Body)
        if err != nil { log.Fatal(err) }
        requestBody := string(r)
        if requestBody == "" { requestBody = "{}" }

        // result strings
        var status int
        var message string
        var mimetype string
        var response string

        var db_query = fmt.Sprintf(
                "select status, message, response, mimetype from endpoint.request(%v, %v, %v, %v::json,%v::json)",
                pq.QuoteLiteral(version),
                pq.QuoteLiteral(req.Method),
                pq.QuoteLiteral(apiPath),
                pq.QuoteLiteral(string(queryStringJSON)),
                pq.QuoteLiteral(string(requestBody)))

        // query endpoint.request()
        err = dbpool.QueryRow(context.Background(), db_query).Scan( &status, &message, &response, &mimetype)

        if err != nil {
            log.Println(err)
            log.Println("\n\n", db_query, "\n\n", req.Proto, req.RequestURI, "\nREQUEST BODY:\n"+string(requestBody), string(queryStringJSON))
            // fmt.Fprintf(os.Stderr, "API request failed: %v\n", err)
            return
        }

        // set mimetype
        w.Header().Set("Content-Type", mimetype)

/*
        // url parts
        io.WriteString(w, "Hello from the REST API.  Here are some stats:\n")
        io.WriteString(w, "RequestURI: "+req.RequestURI+"\n")
        io.WriteString(w, "version: "+version+"\n")
        io.WriteString(w, "apiPath: "+apiPath+"\n")
        io.WriteString(w, "RawQuery: "+req.URL.RawQuery+"\n")
        io.WriteString(w, "Proto: "+req.Proto+"\n\n\n")

        io.WriteString(w, "qs: "+string(queryStringJSON)+"\n\n\n")

        io.WriteString(w, "status: "+fmt.Sprintf("%v",status)+"\n")
        io.WriteString(w, "message: "+message+"\n")
        io.WriteString(w, "mimetype: "+mimetype+"\n")
        io.WriteString(w, "response: "+response+"\n")
*/

        // response body
        io.WriteString(w, response)
    }


    /*
    * resource handler
    *
    * 1. count the number of matching paths in
    *   - endpoint.resource
    *   - endopint.resource_binary
    *   - endpoint.template_route
    * if count > 1, throw a 300 multiple choices
    * if count < 1, throw 404 not found
    *
    * 2. grab the resource or template, serve the content
    */

    resourceHandler := func(w http.ResponseWriter, req *http.Request) {
        // request string
        path := strings.SplitN(req.RequestURI,"?", 2)[0]

        // count matching endpoint.resource
        const match_count_q = `
            select r.id::text, 'resource' as resource_table
            from endpoint.resource r
            where path = %v
            and active = true

            union

            select r.id::text, 'resource_binary'
            from endpoint.resource_binary r
            where path = %v
            and active = true

            union

            select r.id::text, 'template'
            from endpoint.template_route r
            where %v ~ r.url_pattern`
            // and active = true ?

        matches, err := dbpool.Query(context.Background(), fmt.Sprintf(match_count_q, pq.QuoteLiteral(path), pq.QuoteLiteral(path), pq.QuoteLiteral(path)))
        if err != nil {
            fmt.Fprintf(os.Stderr, "Matches query failed: %v\n", err)
            os.Exit(1)
        }
        defer matches.Close()

        var id string
        var resource_table string

        var n int32
        for matches.Next() {
            err = matches.Scan(&id, &resource_table)
            if err != nil {
                return // FIXME
            }
            n++
        }


        // 300 Multiple Choices
        if n > 1 {
            http.Error(w, http.StatusText(http.StatusMultipleChoices), http.StatusMultipleChoices)
            return // FIXME?
        } else {
            // 404 Not Found
            if n < 1 {
                http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)
                return // FIXME?
            }
        }


        var content string
        var content_binary []byte
        var mimetype string

        switch resource_table {
        case "resource":
            const resource_q = `
                select r.content, m.mimetype
                from endpoint.resource r
                    join endpoint.mimetype m on r.mimetype_id = m.id
                where r.id = %v`

            err := dbpool.QueryRow(context.Background(), fmt.Sprintf(resource_q, pq.QuoteLiteral(id))).Scan(&content, &mimetype)
            if err != nil {
                fmt.Fprintf(os.Stderr, "QueryRow failed: %v\n", err)
                os.Exit(1)
            }
            w.Header().Set("Content-Type", mimetype)
            io.WriteString(w, content)

        case "resource_binary":
            const resource_binary_q = `
                select r.content, m.mimetype
                from endpoint.resource_binary r
                    join endpoint.mimetype m on r.mimetype_id = m.id
                where r.id = %v`

            err := dbpool.QueryRow(context.Background(), fmt.Sprintf(resource_binary_q, pq.QuoteLiteral(id))).Scan(&content_binary, &mimetype)
            if err != nil {
                fmt.Fprintf(os.Stderr, "QueryRow failed: %v\n", err)
                os.Exit(1)
            }
            w.Header().Set("Content-Type", mimetype)
            w.Write(content_binary)

        case "template":
            const template_q = `
                select
                    endpoint.template_render(
                        t.id,
                        r.args::json,
                        array_to_json( regexp_matches(%v, r.url_pattern) )
                    ) as content,
                    m.mimetype
                from endpoint.template_route r
                    join endpoint.template t on r.template_id = t.id
                    join endpoint.mimetype m on t.mimetype_id = m.id`

            err := dbpool.QueryRow(context.Background(), fmt.Sprintf(template_q, pq.QuoteLiteral(path))).Scan(&content, &mimetype)
            if err != nil {
                fmt.Fprintf(os.Stderr, "QueryRow failed: %v\n", err)
                os.Exit(1)
            }
            w.Header().Set("Content-Type", mimetype)
            io.WriteString(w, content)
        }
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

    // log.Fatal(http.ListenAndServe(":9000", nil))
    // https://github.com/denji/golang-tls
    log.Fatal(http.ListenAndServeTLS(":4443", "server.crt", "server.key", nil))
}
