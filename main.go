package main

import (
    "context"
    "encoding/json"
    "fmt"
    embeddedPostgres "github.com/aquametalabs/embedded-postgres"
    "github.com/jackc/pgx/v4/pgxpool"
    "github.com/lib/pq"
    "io"
    "io/ioutil"
    "log"
    "net/http"
    "net/url"
    "os"
    "os/exec"
    "os/signal"
    "path/filepath"
    "strings"
    "time"
)

func main() {
log.Print("                                           __")
log.Print("_____    ________ _______    _____   _____/  |______")
log.Print("\\__  \\  / ____/  |  \\__  \\  /     \\_/ __ \\   __\\__  \\")
log.Print(" / __ \\< <_|  |  |  // __ \\|  Y Y  \\  ___/|  |  / __ \\_")
log.Print("(____  /\\__   |____/(____  /__|_|  /\\___  >__| (____  /")
log.Print("     \\/    |__|          \\/      \\/     \\/          \\/")
log.Print("                 [ version 0.3.0 ]")


    log.SetPrefix("[💧 aquameta 💧] ")
    log.Print("Aquameta server... ENGAGE!")
    workingDirectory, err := filepath.Abs(filepath.Dir(os.Args[0]))
    var epg embeddedPostgres.EmbeddedPostgres

    //
    // trap ctrl-c
    //
    c := make(chan os.Signal, 1)
    signal.Notify(c, os.Interrupt)
    go func(){
        for sig := range c {
            if epg.IsStarted() {
                log.Print("Stopping PostgreSQL")
                epg.Stop()

            }
            log.Fatalf("SIG %s - Good day.", sig)
        }
    }()


    //
    // load config
    //

    configFile := workingDirectory+"/conf/boot.toml"
    bootloaderConfigFile := workingDirectory+"/conf/bootloader.toml"
    // TODO: allow override configFile w/ cmd-line args
    // TODO: constants for filenames

    config, err := getConfig(configFile)
    if err != nil {
        log.Printf("Could not load boot configuration file: %s", err)
        log.Printf("Loading default Bootloader configuration instead from %s", bootloaderConfigFile)

        blconfig, err := getConfig(bootloaderConfigFile); if err != nil {
            log.Fatalf("Could not load bootloader config %s: %s", bootloaderConfigFile, err)
        }
        config = blconfig
    }

    //
    // setup embedded database
    //

    if config.Database.Mode == "embedded" {
        //
        // initialize epg w/ config settings
        //

        // TODO: NewDatabase() should be called NewPGServer() or some such... refactor epg
        epg = *embeddedPostgres.NewDatabase(embeddedPostgres.DefaultConfig().
            Username(config.Database.Role).
            Password(config.Database.Password).
            // Host
            Port(config.Database.Port).
            Database(config.Database.DatabaseName).
            Version(embeddedPostgres.V12).
            RuntimePath(config.Database.EmbeddedPostgresRuntimePath).
            StartTimeout(45 * time.Second))

        // has an embedded postgres already been installed?
        log.Printf("Checking for existing embedded server at %s", config.Database.EmbeddedPostgresRuntimePath)
        epgFilesExist := true
        if _, err := os.Stat(config.Database.EmbeddedPostgresRuntimePath); os.IsNotExist(err) {
            // TODO: we probably want some more robust inspection of the directory.
            // Check that it has the binary, and a data directory, and generally looks sane.
            // If it doesn't, QUIT!  (Do NOT install the db here, it might be some other directory
            // that would get overwritten.
            log.Printf("Embedded PostgreSQL server found at %s.", config.Database.EmbeddedPostgresRuntimePath)
            epgFilesExist = false
        }

        // if directory doesn't exist, generate an embedded database there
        if !epgFilesExist {
            log.Printf("Embedded PostgreSQL server not found at %s.  Installing...", config.Database.EmbeddedPostgresRuntimePath)

            if err := epg.Install(); err != nil {
                log.Fatalf("Unable to install PostgreSQL: %v", err)
            }
            log.Printf("PostgreSQL server installed at %s", config.Database.EmbeddedPostgresRuntimePath)
        }

        //
        // start the epg database daemon
        //

        log.Printf("Starting PostgreSQL server from %s...", config.Database.EmbeddedPostgresRuntimePath)
        if err := epg.Start(); err != nil {
            log.Fatalf("Unable to start PostgreSQL: %v", err)
        }
        log.Print("PostgreSQL server started.")

        defer func() {
            log.Print("Stopping PostgreSQL Server...")
            if err := epg.Stop(); err != nil {
                log.Fatalf("Database halt failed: %v", err)
            } else {
                log.Print("Database stopped")
            }
        }()

        //
        // CREATE DATABASE
        //

        if !epgFilesExist {
            if err := epg.CreateDatabase(); err != nil {
                // TODO: create epg.DatabaseExists() method
                // log.Fatalf("Unable to create database: %v", err)
            } else {
                log.Print("PostgreSQL server installed to %s", config.Database.EmbeddedPostgresRuntimePath)
            }
        }
    }



    //
    // connect to database
    //

    connectionString := fmt.Sprintf("postgresql://%s:%s@%s:%d/%s", config.Database.Role, config.Database.Password, config.Database.Host, config.Database.Port, config.Database.DatabaseName)
    log.Printf("Database: %s", connectionString)

    dbpool, err := pgxpool.Connect(context.Background(), connectionString)
    if err != nil {
        log.Fatalf("Unable to connect to database: %v", err)
    }
    log.Print("Connected to database.")
    defer dbpool.Close()


    //
    // pg_settings
    //

    // CLI switch here:  if --debug, else ...
    settingsQueries := [...]string{
        fmt.Sprintf("set log_min_messages='notice'"), // { notice, warning, error, ...}
        fmt.Sprintf("set log_statement='all'"),
    }
    for i := 0; i < len(settingsQueries); i++ {
        rows, err := dbpool.Query(context.Background(), settingsQueries[i])
        if err != nil {
            epg.Stop()
            log.Fatalf("Unable to update settings: %v", err)
        }
        rows.Close()
    }
    log.Print("PostgreSQL settings have been set.")



    //
    // - install aquameta extensions
    //

    var ct int
    dbQuery := fmt.Sprintf("select count(*) as ct from pg_catalog.pg_extension where extname in ('meta','bundle','endpoint','ide','documentation','widget','semantics')")
    err = dbpool.QueryRow(context.Background(), dbQuery).Scan( &ct)
    log.Print("Checking for Aquameta installation....")

    if ct != 7 {

        //
        // install aquameta extensions
        //

        log.Print("Aquameta is not installed on this database.  Installing...")


        if config.Database.Mode == "embedded" {
            exec.Command("/bin/sh", "-c", "cp "+workingDirectory+"/extensions/*/*--*.*.*.sql " + config.Database.EmbeddedPostgresRuntimePath + "/share/postgresql/extension/").Run()
            exec.Command("/bin/sh", "-c", "cp "+workingDirectory+"/extensions/*/*.control " + config.Database.EmbeddedPostgresRuntimePath + "/share/postgresql/extension/").Run()
            log.Print("Extensions copied to PostgreSQL's extensions directory.")
        }

        installQueries := [...]string{
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

        for i := 0; i < len(installQueries); i++ {
            rows, err := dbpool.Query(context.Background(), installQueries[i])
            if err != nil {
                epg.Stop()
                log.Fatalf("Unable to install extensions: %v", err)
            }
            rows.Close()
        }
        log.Print("Extensions were successfully installed.")



        //
        // setup hub remote
        //
        hubRemoteQuery := `insert into bundle.remote_database (foreign_server_name, schema_name, connection_string, username, password)
            values (
                'hub', 'hub',
                'dbname ''aquameta'', host ''hub.aquameta.com'', port ''5432''',
                'anonymous', 'anonymous'
            )`
        _, err := dbpool.Query(context.Background(), hubRemoteQuery)
        if err != nil {
            epg.Stop()
            log.Fatalf("Unable to add bundle.remote_database: %v", err)
        }



        //
        // create superuser
        //

        log.Print("Setting up permissions...")

        superuserQuery := fmt.Sprintf("insert into endpoint.user (email, name, active, role_id) values (%s, %s, true, meta.role_id(%s))",
            pq.QuoteLiteral(config.AquametaUser.Email),
            pq.QuoteLiteral(config.AquametaUser.Name),
            pq.QuoteLiteral(config.Database.Role))
        rows, err := dbpool.Query(context.Background(), superuserQuery)
        if err != nil {
            log.Fatalf("Unable to create superuser: %v", err)
        }
        rows.Close()



        //
        // download and install bundles
        //
/*
        TODO: switch hub install vs local file install, based on CLI

        // hub install over network
        log.Print("Downloading Aquameta core bundles from hub.aquameta.com...")
        bundleQueries := [...]string{
            "select bundle.remote_mount(id) from bundle.remote_database",
            "select bundle.remote_pull_bundle(r.id, b.id) from bundle.remote_database r, hub.bundle b where b.name != 'org.aquameta.core.bundle'",
            "select bundle.checkout(c.id) from bundle.commit c join bundle.bundle b on b.head_commit_id = c.id;" }

        for i := 0; i < len(bundleQueries); i++ {
            log.Printf("Setup query: %s", bundleQueries[i])
            rows, err := dbpool.Query(context.Background(), bundleQueries[i])
            if err != nil {
                log.Fatalf("Unable to install Aquameta bundles: %v", err)
            }
            rows.Close()
        }
*/

        // install from local filesystem
        // TODO: Do this by inspecting the bundles directory?
        log.Print("Installing core bundles from source")
        coreBundles := [...]string{
            "org.aquameta.core.bootloader",
            "org.aquameta.core.endpoint",
            "org.aquameta.core.ide",
            "org.aquameta.core.mimetypes",
            "org.aquameta.core.semantics",
            "org.aquameta.core.widget",
            "org.aquameta.games.snake",
            "org.aquameta.ui.fsm",
            "org.aquameta.ui.layout",
            "org.aquameta.ui.tags",
        }

        for i := 0; i < len(coreBundles); i++ {
            q := "select bundle.bundle_import_csv('"+workingDirectory+"/bundles/"+ coreBundles[i]+"')"
            rows, err := dbpool.Query(context.Background(), q)
            if err != nil {
                epg.Stop()
                log.Fatalf("Unable to install Aquameta bundles: %v", err)
            }
            rows.Close()
        }

        //
        // check out core bundles
        //

        log.Print("Checking out core bundles...")
        rows, err = dbpool.Query(context.Background(), "select bundle.checkout(c.id) from bundle.commit c join bundle.bundle b on b.head_commit_id = c.id")
        if err != nil {
            log.Fatalf("Unable to checkout core bundles: %v", err)
        }
        rows.Close()


        log.Print("Installation complete!")


    }


    //
    // request handlers
    //


    // endpoint API handler

    apiHandler := func(w http.ResponseWriter, req *http.Request) {
        log.Println(req.Proto, req.Method, req.RequestURI)

        // api version, sub-path
        s := strings.SplitN(req.URL.Path,"/",4)
        version, apiPath := s[2], s[3]

        if version != "0.3" {
            log.Print("💩💩💩💩💩💩 Referene to non-0.3 endpoint.")
        }

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

        var dbQuery = fmt.Sprintf(
                "select status, message, response, mimetype from endpoint.request(%v, %v, %v, %v::json, %v::json)",
                pq.QuoteLiteral(version),
                pq.QuoteLiteral(req.Method),
                pq.QuoteLiteral(apiPath),
                pq.QuoteLiteral(queryStringJSON),
                pq.QuoteLiteral(requestBody))

        // query endpoint.request()
        err = dbpool.QueryRow(context.Background(), dbQuery).Scan( &status, &message, &response, &mimetype)

        // unhandled exception in endpoint.request()
        if err != nil {
            log.Printf("💥💥💥💥 API Query failed, unhandled exception: %s", err)
            log.Printf("REQUEST:\nversion: %s\nmessage: %s\nresponse: %s\nmimetype: %s\n\n", version,message,response,mimetype)
            log.Printf("RESPONSE:\ndbQuery: %s\nreq.Proto: %s\nreq.RequestURI: %s\nrequestBody: %s\nqueryStringJSON: %s\n\n",dbQuery, req.Proto, req.RequestURI, requestBody, queryStringJSON)
            return
        }

        w.Header().Set("Content-Type", mimetype)
        w.WriteHeader(status)
        io.WriteString(w, response)
    }


    bootloaderHandler := func(w http.ResponseWriter, req *http.Request) {

        log.Println(req.Proto, req.Method, req.RequestURI)

        // halt
        if req.RequestURI == "/bootloader/halt" {
            log.Print("Bootloader has requested that I halt, so I will halt.")
            if epg.IsStarted() {
                log.Print("Stopping PostgreSQL")
                epg.Stop()
            }

            log.Fatal("Good day.")
        }

        // write config
        if req.RequestURI == "/bootloader/configure" {
            log.Println("Ok I will write out the specified .conf file to disk")
        }
    }


    /*
    * resource handler
    *
    * 1. count the number of matching paths in
    *   - endpoint.resource
    *   - endpoint.resource_binary
    *   - endpoint.template_route
    * if count > 1, throw a 300 multiple choices
    * if count < 1, throw 404 not found
    *
    * 2. grab the resource or template, serve the content
    */

    resourceHandler := func(w http.ResponseWriter, req *http.Request) {
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
        // TODO: Learn to work with UUIDs in Go
        const matchCountQ = `
            select r.id::text, 'resource' as resource_table
            from endpoint.resource r
            where path = %v
            and active = true

            union

            select r.id::text, 'resource_binary'
            from endpoint.resource_binary r
            where path = %v
            and active = true`
            /*

            -- union

            -- select r.id::text, 'resource_function'
            -- from endpoint.resource_function r
            -- where regexp_match(%v, regexp_replace('^' || r.path_pattern || '$', '{\$\d+}', '(\S+)', 'g'))

            union

            select r.id::text, 'template'
            from endpoint.template_route r
            where %v ~ r.url_pattern`
            // and active = true ?
            */

        matches, err := dbpool.Query(context.Background(), fmt.Sprintf(
            matchCountQ,
            pq.QuoteLiteral(path),
            pq.QuoteLiteral(path)))
        if err != nil {
            log.Fatalf("Resource matching query failed: %v", err)
        }
        defer matches.Close()

        var id string
        var resourceTable string

        var n int32
        for matches.Next() {
            err = matches.Scan(&id, &resourceTable)
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
        var contentBinary []byte
        var mimetype string

        switch resourceTable {
        case "resource":
            const resourceQ = `
                select r.content, m.mimetype
                from endpoint.resource r
                    join endpoint.mimetype m on r.mimetype_id = m.id
                where r.id = %v`

            err := dbpool.QueryRow(context.Background(), fmt.Sprintf(resourceQ, pq.QuoteLiteral(id))).Scan(&content, &mimetype)
            if err != nil {
                log.Printf("QueryRow failed: %v", err)
            }
            w.Header().Set("Content-Type", mimetype)
            w.WriteHeader(200)
            io.WriteString(w, content)

        // this is a mess
        /*
        case "resource_function":
            const resourceFunctionQ = `
                select f.path_pattern, m.mimetype
                from endpoint.resource_function r
                    join endpoint.mimetype m on r.mimetype_id = m.id
                    join %v.%v(%xxx)
                where r.id = %v`

            err := dbpool.QueryRow(context.Background(), fmt.Sprintf(resourceFunctionQ, pq.QuoteLiteral(id))).Scan(&content, &mimetype)
            if err != nil {
                log.Printf("QueryRow failed: %v", err)
            }
            w.Header().Set("Content-Type", mimetype)
            w.WriteHeader(200)
            w.Write(contentBinary)
        */

        case "resource_binary":
            const resourceBinaryQ = `
                select r.content, m.mimetype
                from endpoint.resource_binary r
                    join endpoint.mimetype m on r.mimetype_id = m.id
                    join %v.%v(%xxx)
                where r.id = %v`

            err := dbpool.QueryRow(context.Background(), fmt.Sprintf(resourceBinaryQ, pq.QuoteLiteral(id))).Scan(&content, &mimetype)
            if err != nil {
                log.Printf("QueryRow failed: %v", err)
            }
            w.Header().Set("Content-Type", mimetype)
            w.WriteHeader(200)
            w.Write(contentBinary)
        }

            /*
            failed attempt at using pl/go solution
        case "template":
            const templateQ = `
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

            err := dbpool.QueryRow(context.Background(), fmt.Sprintf(templateQ, pq.QuoteLiteral(path))).Scan(&content, &mimetype)
            if err != nil {
                log.Printf("QueryRow failed: %v", err)
            }
            w.Header().Set("Content-Type", mimetype)
            w.WriteHeader(200)
            io.WriteString(w, content)
        case "resource_binary":
            const resourceBinaryQ = `
                select r.content, m.mimetype
                from endpoint.resource_binary r
                    join endpoint.mimetype m on r.mimetype_id = m.id
                where r.id = %v`

            err := dbpool.QueryRow(context.Background(), fmt.Sprintf(resourceBinaryQ, pq.QuoteLiteral(id))).Scan(&contentBinary, &mimetype)
            if err != nil {
                log.Printf("QueryRow failed: %v", err)
            }
            w.Header().Set("Content-Type", mimetype)
            w.WriteHeader(200)
            w.Write(contentBinary)

        }
            */
    }


    // events handler

    eventHandler := func(w http.ResponseWriter, req *http.Request) {
        io.WriteString(w, "Hello from eventHandler!\n" + req.Method + "\n")
    }


    //
    // attach handlers
    //

    // TODO: configure these in the database??

    http.HandleFunc("/bootloader/", bootloaderHandler)
    http.HandleFunc("/endpoint/", apiHandler)
    http.HandleFunc("/event/", eventHandler)
    http.HandleFunc("/", resourceHandler)


    //
    // start http server
    //

    log.Printf("Starting HTTP server\n\n%s://%s:%s%s\n\n",
        config.HTTPServer.Protocol,
        config.HTTPServer.IP,
        config.HTTPServer.Port,
        config.HTTPServer.StartupURL)

//    go func() { // make the HTTPServer the main thread since GUI is disabled
        if config.HTTPServer.Protocol == "http" {
            http.ListenAndServe(config.HTTPServer.IP+":"+config.HTTPServer.Port, nil)
        } else {
            if config.HTTPServer.Protocol == "https" {
                // https://github.com/denji/golang-tls
                log.Fatal(http.ListenAndServeTLS(
                    config.HTTPServer.IP+":"+config.HTTPServer.Port,
                    config.HTTPServer.SSLCertificateFile,
                    config.HTTPServer.SSLKeyFile,
                    nil))
            } else {
                log.Fatal("Unrecognized protocol: "+config.HTTPServer.Protocol)
            }
        }
//    }()

    //
    // start gui
    //

    /*
    log.Printf("HTTP server started, startup URL:\n\n%s://%s:%s%s\n\n",
        config.HTTPServer.Protocol,
        config.HTTPServer.IP,
        config.HTTPServer.Port,
        config.HTTPServer.StartupURL)

    w := webview.New(true)
    defer w.Destroy()
    w.SetTitle("Aquameta Boot Loader")
    w.SetSize(800, 500, webview.HintNone)
    w.Navigate(config.HTTPServer.Protocol+"://"+config.HTTPServer.IP+":"+config.HTTPServer.Port+"/boot")
    w.Run()

     */

    if config.Database.Mode == "embedded" {
        if epg.IsStarted() { epg.Stop() }
    }

    log.Fatal("Good day.")
}
