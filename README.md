# noxDbApi - Stored procedures as REST services.

Stored procedures and UDTF as web services using noxDb for IBM i 

noxDbApi is a simple way to expose Db2 stored procedures as web-services on the IBM i. 
In this examples everything is full open, however you might contain the services 
you expose either by access security or by user defined access rules added to this code - Whatever serves you best.

This application is using IceBreak - however you can easy follow the steps below and use the ILEastic and noxDB 
open source project. You will see in the code that it is actually noxDB is doing all the magic.  

noxDbApi supports Db2 stored procedures on the IBM i with parameters and even if thay returns dynamic result sets.


Look in the example below.


## 1) Creat environment

Installation on your IBM i of `noxDbApi` should be done with `git` which are available via `yum` - you can read more about [yum here](https://bitbucket.org/ibmi/opensource/src/master/docs/yum/).  

On your IBM i 

First `ssh` or  `call qp2term` into your IBM i, install git and clone this repo into the IFS:

```
yum install git
git -c http.sslVerify=false clone https://github.com/sitemule/noxDbApi.git /prj/noxDbApi
``` 

This will create a directory `/prj/noxDbApi`

Now on a 5250 terminal:

```
GO ICEBREAK
ADDICESVR SVRID(noxDbApi) HTTPPATH('/prj/noxdbapi')  TEXT('Stored procedures, UDTF as webservices') SVRPORT(7007)                               
STRICESVR SVRID(noxDbApi)
```


Compile the stored procedure router:

```
CRTICEPGM STMF('/prj/noxDbApi/noxDbApi.rpgle') SVRID(noxDbApi)
````

### Enable noxDbApi in your web config:

Add the noxDbApi in the routing section in you webconfig.xml file in your server root:

```
<routing strict="false">
	<map pattern="^/noxdbapi/" pgm="noxdbapi" lib="*LIBL" />
</routing>
```


## 2) Using stored procedures: 

Procedures can be used if they have:

*	Parameter
*	Return one dynamic result set:

Example:

Build a test stored procedure - paste this into ACS:

```
-- Procedure returns a resultset
--------------------------------
CREATE or REPLACE PROCEDURE  noxDbApi.services_info_list  (
      in service_search_name  varchar(20) default null
)
LANGUAGE SQL 
DYNAMIC RESULT SETS 1

BEGIN

    declare c1 cursor with return for
    select * 
    from   qsys2.services_info
    where  service_search_name is null 
    or     upper(service_name) like '%' concat upper(service_search_name) concat '%';

    open c1;

END; 

comment on procedure noxDbApi.services_info_list is 'Services info List';
comment on parameter noxDbApi.services_info_list (service_search_name is 'Search services by name');

-- Test if the procedure works in ACS:

call noxDbApi.services_info_list (service_search_name => 'ptf');
call noxDbApi.services_info_list ();

``` 



## 3) Into action:

From your browser type the following, where `MY_IBM_I` is the name or TCP/IP address of your system: 
```
http://MY_IBM_I:7007/noxDbAp/noxDbApi
```

The first /noxDbApi is the environmet - the routing name, you can change that in the webconfig.xml "routing" tag

The next /noxDbApi is the schema name. We suply our library `noxDbApi` where we put our procedure - any (user) library from the librarylist is valid to use ( so be carefull) 

It will provide you with a openAPI interface for all stored procedures in this particuæar schema (library) where you can execute the procedures directly ( so be carefull)


