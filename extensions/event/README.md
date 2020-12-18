# Event Module

## Goals

If you've been following the previous chapters, you already know that Aquameta is designed on our first principle of datafication, rethinking each layer in stack as relational data.  We start to see the fruits of our labor and the benefits of systemic consistency here in the events module.

In a "traditional" web stack in 2016, there are different kinds of event systems throughout the stack's various layers.  Git has [git hooks](https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks) for commit events, the file system has [`inotify`](http://man7.org/linux/man-pages/man7/inotify.7.html) for file change events, application-level events can use something like [Django signals](https://docs.djangoproject.com/en/1.9/topics/signals/), we might have a message queue like [celery](http://www.celeryproject.org/) for general purpose message passing.  Among others.

Our goal with `event` is to do all of the above with one system.  Because of Aquameta's first principle of datafication, the idea is that any change that can possibly happen in Aquameta is some kind of data change.

We'll use `event` in the future to keep the DOM in sync with the database, handle pub/sub communication of data change events, and build more advanced coding patterns in the spirit of "live coding".

## Relational diff

To understand what a data change event is, let's start with a simple data set and make some changes to it:

<table width='400' style='border: 2px solid black'>
<tr style='border-bottom: 2px solid black;'><th colspan=3>person</th></tr>
<tr><th>id</th><th>name</th><th>score</th></tr>
<tr><td>1</td><td>Joe Smith</td><td>15</td></tr>
<tr><td>2</td><td>Don Jones</td><td>12</td></tr>
<tr><td>3</td><td>Sandy Hill</td><td>16</td></tr>
<tr><td>4</td><td>Nancy Makowsky</td><td>9</td></tr>
</table>

Now imagine running the following SQL to change the data:
```sql
insert into person (name, score) values ('Don Pablo', 14);
update person set name='Sandy Jones', score=score+3 where id=3;
delete from person where id=4;
```

After the changes:

<table width='400' style='border: 2px solid black'>
<tr style='border-bottom: 2px solid black;'><th colspan=3>person table - after change</th></tr>
<tr><th>id</th><th>name</th><th>score</th></tr>
<tr><td>1</td><td>Joe Smith</td><td>15</td></tr>
<tr><td>2</td><td>Don Jones</td><td>12</td></tr>
<tr><td>3</td><td>Sandy Jones</td><td>19</td></tr>
<tr><td>5</td><td>Don Pablo</td><td>14</td></tr>
</table>

Here's what you might call a "relational diff", highlighting the difference between the two tables:

<table width='400' style='border: 2px solid black'>
<tr style='border-bottom: 2px solid black;'><th colspan=3>person table - inclusive difffd</th></tr>
<tr><th>id</th><th>name</th><th>score</th></tr>
<tr><td>1</td><td>Joe Smith</td><td>15</td></tr>
<tr><td>2</td><td>Don Jones</td><td>12</td></tr>
<tr><td>3</td><td style='background-color: #ff9; border: 1px solid black;'>Sandy Jones</td><td  style='background-color: #ff9; border: 1px solid black;'>19</td></tr>
<tr style='background-color: #f99; border: 1px solid black;'><td>4</td><td>Nancy Makowsky</td><td>9</td></tr>
<tr style='background-color: #9f9; border: 1px solid black;'><td>5</td><td>Don Pablo</td><td>14</td></tr>
</table>

Aquameta's event model for data changes builds on the observation that we can express the "diff" between any two database states as a collection of operations of precisely three types:

<table>
<tr><th>change type</th><th>arguments</th></tr>
<tr><td style='background-color: #9f9; border: 1px solid black;'>row_insert</td><td style='border: 1px solid black'>relation_id, row data</td></tr>
<tr><td style='background-color: #f99; border: 1px solid black;'>delete row</td><td style='border: 1px solid black'>row_id</td></tr>
<tr><td style='background-color: #ff9; border: 1px solid black;'>update field</td><td style='border: 1px solid black'>field_id, new value</td></tr>
</table>

<!--
1. <span style='background-color: #9f9'>create a row</span>
1. <span style='background-color: #f99'>delete a row</span>
1. <span style='background-color: #ff9'>change a field</span>
-->

In this frame, we can express the "delta" between these two tables as a set of these operations:


<table  valign=top>
<tr>
	<th>SQL command</th>
    <th>change type</th>
    <th>arguments</th>
</tr>

<tr>
	<td style='border: 1px solid black'>`insert into person (name, score) values ('Don Pablo', 14);`</td>
    <td style='background-color: #9f9; border: 1px solid black;'>row_insert</td>
    <td style='border: 1px solid black'>public.person, { id: 5, name: Don Pablo, score: 14 }</td>
</tr>

<tr>
	<td style='border: 1px solid black'>`delete from person where id=4;`</td>
    <td style='background-color: #f99; border: 1px solid black;'>row_delete</td>
    <td style='border: 1px solid black'>public.person.4</td>
</tr>

<tr>
	<td rowspan=2 style='border: 1px solid black'>`update person set name='Sandy Jones', score=score+3 where id=3;`</td>
	<td style='background-color: #ff9; border: 1px solid black;'>field_update</td>
    <td style='border: 1px solid black'>public.person.3.name, Sandy Jones</td>
</tr>

<tr>
	<td style='background-color: #ff9; border: 1px solid black;'>field_update</td>
    <td style='border: 1px solid black'>public.person.3.score, 19</td>
</tr>
</table>

<!--
1. <span style='background-color: #9f9'>create row</span> person { id: 5, name: Don Pablo, score: 14 }
1. <span style='background-color: #f99'>delete row</span> person id=4
1. <span style='background-color: #ff9'>update field</span> person id=3 { name: Sandy Jones }
1. <span style='background-color: #ff9'>update field</span> person id=3 { score: 19 }
-->

You could imagine a log of changes like the one above going in parallel to the PostgreSQL query log.  But rather than logging the commands that have been executed, it logs the resultant changes of those commands.  These three simple operations (<span style='background-color: #9f9'>row\_insert</span>, <span style='background-color: #f99'>row\_delete</span>, <span style='background-color: #ff9'>field\_update</span>) encompass *all the ways data can change*.

So that covers data changes, but what about schema changes, what some call "migrations"?  Say we were to add an `age` column to the table above:

```sql
alter table public.person add column age integer;
```

In Aquameta, schema changes can be represented as data changes as well, via [meta](), our writable system catalog.  The column could have just as well been created via an `insert` into the `meta.column` table:

```sql
insert into meta.column (schema_name, relation_name, name, type) values ('public','person','age', 'integer');
```

So, we can also represent schema changes in our event log:

<table  valign=top>
<tr>
	<th>SQL command</th>
    <th>change type</th>
    <th>arguments</th>
</tr>

<tr>
	<td style='border: 1px solid black'>alter table public.person add column age integer;</td>
    <td style='background-color: #9f9; border: 1px solid black;'>row_insert</td>
    <td style='border: 1px solid black'>meta.column, { schema_name: public, relation_name: person, name: age, type: integer }</td>
    </tr>
</table>

The event module doesn't yet support schema changes, but it's certainly possible via PostgreSQL's [DDL events](http://www.postgresql.org/docs/current/static/event-triggers.html) mechanism.

## Example Usage

Ok, let's take a look at the event system in action.

###Sessions
To identify where to send events, we use `session`, an abstract entity that represents one use session, say a browser tab or a cookie session.  In Aquameta they are the primary key for persistent state, and can be used across PostgreSQL connections and by multiple connections and roles at the same time.  They serve as a kind of inbox for events, among other things.  Users create sessions and can detatch and reattach to them, or the web server can create them.

Let's create a new session:

```sql
aquameta=# select session_create();
            session_create
--------------------------------------
 ceb2c0cf-9985-454b-bc79-01706b931a3b
(1 row)
```

### Subscriptions

Once a session has been created, they can subscribe to data changes at various levels of granularity, an entire table, just one specific row, or just one specific field.  Here's the API:

1. **`event.subscribe_table( meta.relation_id )`** - generates row\_insert, row\_delete, field\_change
1. **`event.subscribe_row( meta.row_id )`** - generates field\_change, row\_delete
1. **`event.subscribe_field( meta.field_id )`** - generates field\_change, row\_delete
1. **`event.subscribe_column( meta.column_id )`** - generates field\_change, row\_delete, row_insert


```sql
aquameta=# select  subscribe_table(meta.relation_id('widget','machine'));
           subscribe_table            
--------------------------------------
 ac944107-7679-4987-919b-9f3f39cfdf70
(1 row)
```

Then events come through via PostgreSQL `NOTIFY` messages:

```sql
aquameta=# insert into widget.machine values (DEFAULT);
INSERT 0 1
Asynchronous notification "92841351-8c73-4548-a801-e89c626b9ec0" with payload "{"operation" : "insert", "subscription_type" : "table", "row_id" : {"pk_column_id":{"relation_id":{"schema_id":{"name":"widget"},"name":"machine"},"name":"id"},"pk_value":"70e63984-1b70-4324-b5f1-6b6efca09169"}, "payload" : {"id":"70e63984-1b70-4324-b5f1-6b6efca09169"}}" received from server process with PID 22834.
aquameta=# 
```

## Conclusion
Together, it's a dead simple data change event system.  It is highly general purpose, because it's positioned immediately atop our first principle of datafication.  Everything that we'll build in Aquameta further up the stack can have a consistent and uniform event model.
