quameta v0.3
=============


START!
------

Go users:

```bash
# change this to `go get` ?
git clone https://github.com/aquametalabs/aquameta.git
cd aquameta
go build
./scripts/build-extensions.sh
./aquameta
```

{ [Download](http://aquameta.com/download) | [Documentation](http://aquameta.org/docs) }
----------------------------------------------------------------------------------------

Status
------

Aquameta is an experimental project, still in early stages of development.  It is not suitable for production development and should not be used in an untrusted or mission-critical environment.

Introduction
------------

People say the dawn of the Information Age was about wires and semiconductors.  But consider the humble relational database.

From my seat, Edgar Codd kind of figured it all out.

The year was 1969, and Edgar F. (Ted) Codd revealed his conception of the Relational Model, a general purpose algebra for data management.  If correct, his model, he proported, should be able to go into any domain of complexity and serve as an adequate abstraction for representing it, slicing and dicing it and infinite ways, and generally making sense of it.

The relational model, and the relational databases that followed, were the foundation of the information age, at least to a person interested in data.  50 years later, it remains the most popular model for databases, and certainly not without a fight.

It sure looks like Codd got something right.  The humble relational database is still king of the information jungle.  If history is any indicator, it is the best tool us crazy humans have found for making sense of things.

Well, Aquameta is about making sense of things.  It is a tool for interacting with the world through the lense of data.

The world could learn a lot from old Edgar F. Codd about how to make sense of things.  Us data hackers really have a special power, and it's high time we show we show the rest of the world how it's done.

Aquameta is a tool for looking at the world through the lense of data.  It's designed to make the language of data as accessible as possible, without dumbing it down.  To programmers, you might think of Aquameta as a "PostgreSQL Admin GUI".  But this ain't your grandma's PGAdmin.  (Sorry PGAdmin! :))

Here's why.


First Princples
---------------

Under the hood, Aquameta has really internalized Codd's Relational Model -- to an arguably absurd degree.

Here's a thought experiment:  What if we pretended for a minute that today's programming ecosystem wasn't a sprawling jungle of almost limitless complexity, but instead, "just another customer's domain knowledge"?  What if we treated our own dev environment the same as we would a new customer who wants to manage her baseball card collection or keep inventory in their warehouse?  

I'll take a guess what old Edgar Codd would do:  Put everything in the database!

Aquameta is the result of many years of exploring the outcomes of starting from this first principle.  We've modeled the web stack and the database *as relational data*.  The result is a huge database schema that, while daunting from a distance, should be instantly familiar to anyone who already knows web development.  It is everything you already know, just represented in the language of data.

Through this process of exploring a "datafied" web stack, we have climbed many mountains, explored many valleys, seen the lay of the land, and can say with 100% certainty:

This is the new hottness.  This is where the industry inevitably MUST go if we want to leave the bad old days behind.

You know that feeling that an experienced programmer has about the industry?  That feeling that says something is deeply flawed about how we develop software?  That feel is true and correct!  Here's why:

The software industry doesn't have a shared information model whose foundation is a mathematical algebra. Instead we have syntax.  Lots of it!  We have a bunch of files and directories.  We call this modern, but the ghastly consequences of this evolutionary misstep can be seen everywhere -- once you see it.

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


User Experience
---------------

Enough already.  How about some screen shots.

`hi i am some screenshots`


License
-------

Aquameta Core is currently distributed under the GNU Public License (GPL).  

We don't have a legal team to help us make all the best decisions here, but the intention is to follow in the footsteps of Linux:  Provide an open source core that must remain open source, but let users develop and license software built with Aquameta as they see fit.

<!--

About
-----

Aquameta has been the life project of Eric Hanson for close to 20 years
off-and-on.  Functional prototypes have been developed in XML, RDF and MySQL,
but PostgreSQL is the first database discovered that has the functionality
necessary to achieve something close to practical.

Technical goals of the project include:
- Allow complete management of the database using only INSERT, UPDATE and DELETE commands (expose the DDL as DML)
- Version control of relational data
- Reified architecture, where the entire system is self-defined as data, and as such can evolve using only data manipulation
- Remote push/pull of commits to relational VCS
- Access and manipulate the database as a file system from the command prompt
- Access and manipulate the file system as relational data from the SQL prompt
- Internal event system for pub/sub of changes to tables, columns or rows
- Modular web interface components ("widgets") made of HTML, CSS, Javascript, that are self-contained, manage their own dependencies, accept input arguments, can instantiate other widgets, and can emit events that other widgets can subscribe to
- "Semantic decoration" allows the user to associate UI components with schema components (relations, columns, data types), auto-generate simple CRUD UIs, and progressively enhance a UI by overriding sensible defaults with custom widgets
- Pub/sub notification let peers download new content from each other as it comes available without polling
- Users communicate with each other by exchanging structured, relational data
- Decentralized P2P network with no single point of failure
- Decentralize the web
- Datafy the programming stack
- Deprecate the file system

Human goals:
- Teach people to speak the language of data
- Convert word-based knowledge and information to structured knowledge and information
- Stretch a net of approximate categorization across our earth

The database gives developers an almost miraculous power.  It is a general
purpose tool for making sense of the world, poised in every direction.  It lets
programmers dive into any domain of complexity, across wildly diverse
landsapes, with confidence that they have an adequate tool for modeling the
complexity and making sense of it all.


With the database, they can model any new world, identify all the categories,
choose the right distinctions within those catagories, bring in all the facts,
put them in the right buckets, and change around the buckets on the fly as they
learn more.


* [demo video](https://www.youtube.com/watch?v-ZOpj8lvNJtg)
* [get started](docs/quickstart.md)
* [cheat sheet](docs/cheatsheet.md)
* [TWiT FLOSS Weekly](https://www.youtube.com/watch?v-G0C8AsXNPAU)

-->
