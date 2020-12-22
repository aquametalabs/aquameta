Aquameta v0.3
=============


START!
------

[Golang](https://golang.org/) install:

```bash
# change this to `go get` ?
git clone https://github.com/aquametalabs/aquameta.git
cd aquameta
go build
./aquameta
```

{ [Download](http://aquameta.com/download) | [Demo](http://aquameta.com/demo) | [Documentation](http://aquameta.org/docs) }
-----------------------------------------------

Status
------

Aquameta is an experimental project, still in early stages of development.  It is not suitable for production development and should not be used in an untrusted or mission-critical environment.

Introduction
------------

People say the dawn of the Information Age was about wires and semiconductors.  But consider the humble relational database.

From my seat, Edgar Codd kind of figured it all out.

The year was 1969, and Edgar F. (Ted) Codd revealed his conception of the Relational Model, a general purpose algebra for data management.  If correct, his model, he proported, should be able to go into any domain of complexity and serve as an adequate abstraction for representing it, slicing and dicing it in infinite ways, and generally making sense of it.

The relational model, and the relational databases that followed, were the foundation of the information age, at least to a person interested in data.  50 years later, it remains the most popular model for databases -- and certainly not without a fight.

It sure looks like Codd got something right.  The humble relational database is still king of the information jungle.  If history is any indicator, it is the best tool us crazy humans have found for making sense of things.

Well, Aquameta is about making sense of things.  It is a tool for interacting with the world through the lense of data.

The world could learn a lot from old Edgar F. Codd about how to make sense of things.  Us data hackers really have a special power, and it's high time we show we show the rest of the world how it's done.

Aquameta is a tool for seeing the world through the lense of data.  It's designed to make the language of data as accessible as possible, without dumbing it down.  To programmers, you might think of Aquameta as a "PostgreSQL Admin GUI".  But this ain't your grandma's PGAdmin.  (Sorry PGAdmin! :))

Here's why.


First Princples
---------------

Under the hood, Aquameta has really internalized Codd's Relational Model -- to an arguably absurd degree.

Here's a thought experiment:  What if we pretended for a minute that today's programming ecosystem wasn't a sprawling jungle of almost limitless complexity, but instead, "just another customer's domain knowledge"?  What if we treated our own dev environment the same as we would a new customer who wants to manage her baseball card collection or keep inventory in their warehouse?  

I'll take a guess what old Edgar Codd would do:  Put everything in the database!

Aquameta is the result of many years of exploring the outcomes of this thought experiment.  We've modeled the web stack and the database *as relational data*, and prototyped the tools for making this a conceivably pleasant experience.  The result is a huge database schema that, while daunting from a distance, should be instantly familiar to anyone who already knows web development.  It is everything you already know, just represented in the language of data.

Through this process of exploring a "datafied" web stack, we have climbed many mountains, explored many valleys, seen the lay of the land, and can say with 100% certainty:

This is the new hottness.  This is where the industry inevitably MUST go if we want to leave the bad old days behind.

You know that feeling that an experienced programmer has about the industry?  That feeling that says something is deeply flawed about how we develop software?  That feel is true and correct!  Here's why:

The software industry doesn't have a shared information model whose foundation is a mathematical algebra. Instead we have syntax.  Lots of it!  We have files, and directories.  The files plus syntax paradigm can't manage the complexity we're throwing at it, and the consequences of this evolutionary misstep are everywhere -- once you see it.

Come take a look.


Architecture
------------

Alright, so what is it and how does it work?

On the surface, Aquameta looks like a rapid prototyping web dev IDE, or maybe a PostgreSQL admin GUI, or maybe a GUI for git.  But under the hood it is just a bunch of schema for your data.

Here's an example, the endpoint schema:

`Hi I am a schema.`

Aquameta has five PostgreSQL extensions, each of which roughly corresponds to a layer or tool that's essential to the web stack.  As just a big database, It has ~60 tables, ~50 views and ~90 stored procedures.  The HTTP Server is programmed in Go, but it is just a thin wrapper that hands off requests to a stored procedure in PostgreSQL:


```
endpoint.request('GET','/index.html','...query string args...`,`...post vars...`)
```
PostgreSQL handles it from there.


Aquameta contains five core PostgreSQL extensions, which together proport themselves to be a web development stack:

- [meta](extensions/meta) - Writable system catalog for PostgreSQL, making most database admin tasks possible as data manipulation.
- [bundle](extensions/bundle) - Version control system similar to `git` but for database rows instead of files.
- [event](extensions/event) - Lets you watch tables, rows or columns for inserts, updates and deletes, and get a notification as such.
- [http](extensions/endpoint) - Minimalist web server that provides a REST API to the database and simple static/templated resource hosting.
- [widget](extensions/widget) - Minimalist web component framework that says, "Widgets are made up of HTML, CSS and Javascript, and have inputs.  Proceed."
- is semantics in core?

Poke around the [schemas]() to see how things look, [endpoint]() is a good place to start.

Aquameta is a very unopinionated stack, except for that one big opinion about everything being data.  From there, our tables are intended to just express "how the web works" and leave the rest up to you.  You can use any client-side framework you please, and the backend supports several different [procedural languages]().

It's tuples all the way down.  Well, that's the idea anyway.  Of course there is still the Operating System down below PostgreSQL, with all it's "files" and so forth.  But if we follow this idea to it's natural conclusions, we would make all that look a lot different too.

Aquameta's long-term trajectory is to find the places where putting things in the database makes them easier to work with.  We think there is a lot more of opportunity here.  If you're up for an adventure into the unknown, I hope you'll give it a try.


License
-------

Aquameta Core is currently distributed under the GNU Public License (GPL) version 3.

We don't have a legal team to help us make all the best decisions here, but the intention is to follow in the footsteps of Linux:  Provide an open source core that must remain open source, but let users develop and license software built with Aquameta as they see fit.

