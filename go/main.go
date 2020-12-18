package main

import (
    "context"
    "encoding/json"
    "fmt"
    "io"
    "io/ioutil"
    "log"
    "net/http"
    "net/url"
    "os"
    "os/exec"
    "os/signal"
    "runtime"
    "strings"
    "time"

    embeddedPostgres "github.com/aquametalabs/embedded-postgres"
    "github.com/jackc/pgx/v4/pgxpool"
    "github.com/lib/pq"
    "github.com/webview/webview"
)

func main() {
    fmt.Println("[ aquameta ] Aquameta daemon... ENGAGE!")
    config := GetConfig()
    fmt.Printf("[ aquameta ] Webserver: %s:%s\n", config.Webserver.IP, config.Webserver.Port)



    // 
    // initialize the database
   //

    epg := embeddedPostgres.NewDatabase(embeddedPostgres.DefaultConfig().
        Username(config.Database.User).
        Password(config.Database.Password).
        // Host
        Port(config.Database.Port).
        Database(config.Database.DatabaseName).
        Version(embeddedPostgres.V12).
        RuntimePath(config.Database.RuntimePath).
        StartTimeout(45 * time.Second))

    // trap ctrl-c
    c := make(chan os.Signal, 1)
    signal.Notify(c, os.Interrupt)
    go func(){
        for sig := range c {
            if epg.IsStarted() {
                epg.Stop()
                runtime.Goexit()
            }
            fmt.Printf("[ aquameta ] EYYYYYYYYYYYYYY stop it. %s", sig)
            runtime.Goexit()
            os.Exit(0)
        }
    }()

    //
    // install postgres if it doesn't exist
    //

    createDatabase := false
    if _, err := os.Stat(config.Database.RuntimePath); os.IsNotExist(err) {
        createDatabase = true
        fmt.Println("[ aquameta ] PostgreSQL server is not installed.  Installing...")
        if err := epg.Install(); err != nil {
            fmt.Fprintf(os.Stderr, "[ aquameta ] Unable to install PostgreSQL: %v\n", err)
            runtime.Goexit()
        }
        fmt.Println("[ aquameta ] PostgreSQL server installed at %s", config.Database.RuntimePath)
    } else {
        fmt.Println("[ aquameta ] PostgreSQL is already installed (%s).", config.Database.RuntimePath)
    }


    //
    // start the database daemon
    //

    fmt.Println("[ aquameta ] Starting PostgreSQL server...")
    if err := epg.Start(); err != nil {
        fmt.Fprintf(os.Stderr, "[ aquameta ] Unable to start PostgreSQL: %v\n", err)
        runtime.Goexit()
    }
    fmt.Println("[ aquameta ] PostgreSQL daemon started.")

    //
    // create the database
    //

    if createDatabase {
        fmt.Println("[ aquameta ] PostgreSQL database does not exist, creating...")
        if err := epg.CreateDatabase(); err != nil {
            fmt.Fprintf(os.Stderr, "[ aquameta ] Unable to create database: %v\n", err)
            runtime.Goexit()
        } else {
            fmt.Println("[ aquameta ] PostgreSQL database created.")
        }

    }

    defer func() {
        if err := epg.Stop(); err != nil {
            fmt.Fprintf(os.Stderr, "[ aquameta ] SHEEEIT cant stop.")
        } else {
            fmt.Fprintf(os.Stdout, "[ aquameta ] Database stopped")
        }
    }()





    //
    // connect to database
    //

    connectionString := fmt.Sprintf("postgresql://%s:%s@%s:%d/%s", config.Database.User, config.Database.Password, config.Database.Host, config.Database.Port, config.Database.DatabaseName)
    fmt.Println("[ aquameta ] Database: ", connectionString);

    dbpool, err := pgxpool.Connect(context.Background(), connectionString)
    if err != nil {
        fmt.Fprintf(os.Stderr, "[ aquameta ] Unable to connect to database: %v\n", err)
        runtime.Goexit()
    }
    fmt.Println("[ aquameta ] Connected to database.")
    defer dbpool.Close()

    //
    // enable logging
    //

    dbpool.Query(context.Background(), "set log_min_messages=LOG")
    dbpool.Query(context.Background(), "set log_statement='all'")
    fmt.Println("[ aquameta ] Enabled logging....")




    //
    // check that aquameta's required extensions are installed
    //

    db_query := fmt.Sprintf(`
select count(*) as ct from pg_catalog.pg_extension
    where (extname='meta' and extversion = '0.2.0')
        or (extname='bundle' and extversion = '0.2.0')
        or (extname='endpoint' and extversion = '0.3.0')
    `)

    var ct int
    err = dbpool.QueryRow(context.Background(), db_query).Scan( &ct)
    fmt.Println("[ aquameta ] Checking for Aquameta installation....")

    if ct != 3 {
        fmt.Println("[ aquameta ] Aquameta is not installed on this database.  Installing...")
        exec.Command("/bin/sh", "-c", "cp ./extension/* " + config.Database.RuntimePath + "/share/postgresql/extension/").Run()
        fmt.Println("[ aquameta ] Extensions copied to PostgreSQL's extensions directory.")

        install_queries := [...]string{
            "create extension if not exists hstore schema public",
            "create extension if not exists dblink schema public",
            "create extension if not exists \"uuid-ossp\"",
            "create extension if not exists pgcrypto schema public",
            "create extension if not exists postgres_fdw",
            "create extension pg_catalog_get_defs schema pg_catalog",
            "create extension meta",
            "create extension bundle",
            "create extension event",
            "create extension endpoint",
            "create extension widget",
            "create extension semantics",
            "create extension ide",
            "create extension documentation"}

        for i := 0; i < len(install_queries); i++ {
            rows, err := dbpool.Query(context.Background(), install_queries[i])
            if (err != nil) {
                fmt.Fprintf(os.Stderr, "[ aquameta ] Unable to install Aquameta extensions: %v\n", err)
                runtime.Goexit()
            }
            rows.Close()
        }
        fmt.Println("[ aquameta ] Aquameta extensions were successfully installed.")



        //
        // download and install bundles
        //


        // hub install over network
/* offline only until hub is @v0.3.0
        fmt.Println("[ aquameta ] Downloading Aquameta core bundles from hub.aquameta.com...")
        hub_bundle_queries := [...]string{
            "insert into bundle.remote_database (foreign_server_name, schema_name, host, port, dbname, username, password) values ('hub','hub','hub.aquameta.com',5432,'aquameta','anonymous','anonymous')",
            "select bundle.remote_mount(id) from bundle.remote_database",
            "select bundle.remote_pull_bundle(r.id, b.id) from bundle.remote_database r, hub.bundle b where b.name != 'org.aquameta.core.bundle'",
            "select bundle.checkout(c.id) from bundle.commit c join bundle.bundle b on b.head_commit_id = c.id;" }

        for i := 0; i < len(bundle_queries); i++ {
            fmt.Fprintf(os.Stderr, "[ aquameta ] Setup query: %s\n", bundle_queries[i])
            rows, err := dbpool.Query(context.Background(), bundle_queries[i])
            if (err != nil) {
                fmt.Fprintf(os.Stderr, "[ aquameta ] Unable to install Aquameta bundles: %v\n", err)
                runtime.Goexit()
            }
            rows.Close()
        }
*/

        // install from local filesystem
        fmt.Println("[ aquameta ] Installing core bundles from source")
        core_bundles := [...]string{
            "org.aquameta.core.docs",
            "org.aquameta.core.endpoint",
            "org.aquameta.core.ide",
            "org.aquameta.core.mimetypes",
            "org.aquameta.core.semantics",
            "org.aquameta.core.widget",
            "org.aquameta.games.snake",
            "org.aquameta.templates.simple",
            "org.aquameta.ui.admin",
            "org.aquameta.ui.auth",
            "org.aquameta.ui.bundle",
            "org.aquameta.ui.dev",
            "org.aquameta.ui.event",
            "org.aquameta.ui.fsm",
            "org.aquameta.ui.layout",
            "org.aquameta.ui.tags",

            "com.aquameta.datasphere",
            "com.aquameta.greatsphere",
            "com.aquameta.helix",
            "com.aquameta.cred.erichanson"}
//            "com.aquameta.app.wikiviews"}

        for i := 0; i < len(core_bundles); i++ {
            q := "select bundle.bundle_import_csv('/opt/aquameta/bundles-enabled/"+core_bundles[i]+"')"
            fmt.Fprintf(os.Stderr, "[ aquameta ] Import query: %s\n", q)
            rows, err := dbpool.Query(context.Background(), q)
            if (err != nil) {
                fmt.Fprintf(os.Stderr, "[ aquameta ] Unable to install Aquameta bundles: %v\n", err)
                runtime.Goexit()
            }
            rows.Close()
        }

        //
        // check out core bundles
        //

        fmt.Println("[ aquameta ] Checking out core bundles...")
        rows, err := dbpool.Query(context.Background(), "select bundle.checkout(c.id) from bundle.commit c join bundle.bundle b on b.head_commit_id = c.id")
        if (err != nil) {
            fmt.Fprintf(os.Stderr, "[ aquameta ] Unable to checkout core bundles: %v\n", err)
            runtime.Goexit()
        }
        rows.Close()


        //
        // create superuser
        //

        fmt.Println("[ aquameta ] Setting up permissions...")

        superuser_query := fmt.Sprintf("insert into endpoint.user (email, name, active, role_id) values (%s, %s, true, meta.role_id(%s))",
            pq.QuoteLiteral(config.User.Email),
            pq.QuoteLiteral(config.User.Name),
            pq.QuoteLiteral(config.Database.User))
        rows, err = dbpool.Query(context.Background(), superuser_query)
        if (err != nil) {
            fmt.Fprintf(os.Stderr, "[ aquameta ] Unable to create superuser: %v\n", err)
            runtime.Goexit()
        }
        rows.Close()

        fmt.Println("[ aquameta ] Installation complete!")


    }


    //
    // request handlers
    //


    // endpoint API handler

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
                "select status, message, response, mimetype from endpoint.request(%v, %v, %v, %v::json, %v::json)",
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
        /*
        w.Header().Set("Access-Control-Allow-Origin", "https://cdn.jsdelivr.net")
        w.Header().Set("Access-Control-Allow-Origin", "http://cdn.jsdelivr.net")
        w.Header().Set("Access-Control-Allow-Origin", "http://127.0.0.1")
        w.Header().Set("Access-Control-Allow-Origin", "https://127.0.0.1")
        w.Header().Set("Access-Control-Allow-Methods", "POST, GET, OPTIONS, PUT, DELETE")
        w.Header().Set("Access-Control-Allow-Headers", "Accept, Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization")
"
        if (*req).Method == "OPTIONS" {
            return
        }
        */

        log.Println(req.Proto, req.Method, req.RequestURI)


        // path
        // path := strings.SplitN(req.RequestURI,"?", 2)[0]
        path, err := url.QueryUnescape(req.URL.Path)
        if err != nil { log.Fatal(err) }

        // query string
        /*
        m, err := url.ParseQuery(req.URL.RawQuery)
        if err != nil { log.Fatal(err) }
        */

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
            fmt.Fprintf(os.Stderr, "[ aquameta ] Matches query failed: %v\n", err)
            runtime.Goexit()
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
                fmt.Printf("QueryRow failed: %v\n", err)
                runtime.Goexit()
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
                runtime.Goexit()
            }
            w.Header().Set("Content-Type", mimetype)
            w.Write(content_binary)

        case "template":
            const template_q = `
                select
                    endpoint.template_render(
                        t.id::text, -- FIXME
                        r.args::json::text, -- FIXME
                        (array_to_json( regexp_matches(%v, r.url_pattern) ))::text -- FIXME
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

    fmt.Println("[ aquameta ] Starting HTTP server...")

    go func() {
        if( config.Webserver.Protocol == "http" ) {
            log.Fatal(http.ListenAndServe(config.Webserver.IP+":"+config.Webserver.Port, nil))
        } else {
            if( config.Webserver.Protocol == "https" ){
                // https://github.com/denji/golang-tls
                log.Fatal(http.ListenAndServeTLS(
                    config.Webserver.IP+":"+config.Webserver.Port,
                    config.Webserver.SSLCertificateFile,
                    config.Webserver.SSLKeyFile,
                    nil))
            } else {
                log.Fatal("Unrecognized protocol: "+config.Webserver.Protocol)
            }
        }
    }()

    //
    // start gui
    //

    w := webview.New(true)
    defer w.Destroy()
    w.SetTitle("Aquameta Yo")
    w.SetSize(800, 600, webview.HintNone)
    w.Navigate(config.Webserver.Protocol+"://127.0.0.1:"+config.Webserver.Port+"/")
    w.Run()

}
