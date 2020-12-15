//must be main package

package main

import (
    "log"
    "strings"
    "time"
    "fmt"

    "gitlab.com/microo8/plgo"
    "github.com/robertkrimen/otto"
)

func Meh() {
    //NoticeLogger for printing notice messages to elog
    logger := plgo.NewNoticeLogger("", log.Ltime|log.Lshortfile)
    logger.Println("meh")
}

//ConcatAll concatenates all values of an column in a given table
func ConcatAll(tableName, colName string) string {
    //ErrorLogger for printing error messages to elog
    logger := plgo.NewErrorLogger("", log.Ltime|log.Lshortfile)
    db, err := plgo.Open() //open the connection to DB
    if err != nil {
        logger.Fatalf("Cannot open DB: %s", err)
    }
    defer db.Close() //db must be closed
    query := "select " + colName + " from " + tableName
    stmt, err := db.Prepare(query, nil) //prepare an statement
    if err != nil {
        logger.Fatalf("Cannot prepare query statement (%s): %s", query, err)
    }
    rows, err := stmt.Query() //execute statement
    if err != nil {
        logger.Fatalf("Query (%s) error: %s", query, err)
    }
    var ret string
    for rows.Next() { //iterate over the rows
        var val string
        rows.Scan(&val)
        ret += val
    }
    return ret
}

//CreatedTimeTrigger is an trigger function
//trigger function must have the first argument of type *plgo.TriggerData
//and must return *plgo.TriggerRow
func CreatedTimeTrigger(td *plgo.TriggerData) *plgo.TriggerRow {
    td.NewRow.Set(4, time.Now()) //set the 4th column to now()
    return td.NewRow //return the new modified row
}

//ConcatArray concatenates an array of strings
//function arguments (and return values) can be also array types of the golang builtin types
func ConcatArray(strs []string) string {
    return strings.Join(strs, "")
}

//This used to be uuid and json, but plgo doesnt know how to create functions with either of those types.
//Fun fact, putting a single quote in one of these comments breaks build for some unholy reason.
func Template_Render(template_id string, route_args string, url_args string) string {
    fmt.Printf("-----------------------\nTemplate_Render" + template_id + ", "+route_args+", "+url_args+"\n\n")
    //ErrorLogger for printing error messages to elog
    logger := plgo.NewErrorLogger("", log.Ltime|log.Lshortfile)

    // open db
    db, err := plgo.Open() //open the connection to DB
    if err != nil {
        logger.Fatalf("Cannot open DB: %s", err)
    }
    defer db.Close() //db must be closed


    // get template

    query := "select content from endpoint.template where id::text = '" + template_id + "'" // FIXME: pg_quote_literal
    stmt, err := db.Prepare(query, nil) //prepare an statement
    if err != nil {
        logger.Fatalf("Cannot prepare query statement (%s): %s", query, err)
    }
    rows, err := stmt.Query() //execute statement
    if err != nil {
        logger.Fatalf("Query (%s) error: %s", query, err)
    }
    var template string
    rows.Next()
    rows.Scan(&template)


    // get doT.js

    query = "select code from endpoint.js_module where name='doT'"
    stmt, err = db.Prepare(query, nil) //prepare an statement
    if err != nil {
        logger.Fatalf("Cannot prepare query statement (%s): %s", query, err)
    }
    rows, err = stmt.Query() //execute statement
    if err != nil {
        logger.Fatalf("Query (%s) error: %s", query, err)
    }
    var doT string
    rows.Next()
    rows.Scan(&doT)

    // render template

    vm := otto.New()
    fmt.Println("RUNNING THE DOT LIBRARY....."+doT)
    vm.Run(doT)

    if otto_value, err := vm.Get("doT"); err == nil {
        fmt.Println("vm.Get doT")
        if doT_obj, err := otto_value.ToString(); err == nil {
            fmt.Println("otto_val.ToString()")
            fmt.Println("doT: "+doT_obj)
        }
    }


//    logger.Println("",doT)

    vm_code := `
        context = {};
        context.url_args = ` + url_args + `;
        context.route_args = ` + route_args + `;
        var template_function = doT.template(template);
        // letresult = template_function(context);
        const result = 'HELLLLLOO FROM VM';
   `
    fmt.Println("VM_CODE IS: ", vm_code)
    fmt.Println("Running vm_code.....")
    vm.Run(vm_code)
    fmt.Println("Ran vm_code.....")


    var result string
    if otto_value, err := vm.Get("result"); err == nil {
        fmt.Println("vm.Get ")
        if result, err := otto_value.ToString(); err == nil {
            fmt.Println("otto_val.ToString()")
            fmt.Println("RESULT: "+result)
        } else {
            fmt.Println("YEEEEEEEEEEEEEEEEEEEEEEEEEEEEK!")
        }
    }

    return result

}
