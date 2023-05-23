# noxDbAPI - SQL routines as web-services.

Stored procedures, UDTF and scalar functions as web services using noxDb for IBM i 

noxDbAPI is a simple way to expose Db2 stored procedures, UDTF and scalar functions as web-services on the IBM i. 

In this example everything is fully open, however you might contain the services 
you expose either by access security or by user defined access rules added to this code - Whatever serves you best.

This application is using IceBreak - however you can easily follow the steps below and use the ILEastic and noxDB 
open source project. You will see in the code that it is actually noxDB that is doing all the magic.  

## What is supported

noxDbAPI supports Db2 stored procedures, UDTF and scalar functions. 

Stored procedures will be handled by http "GET" operations if they: 
1) have only input parameters
2) returns one dynamic result set.

Input parameters will be query-string parameters. 


Stored procedures will be handled by http "POST" operations if they: 
1) have input parameters
2) have output parameters
3) have inout parameters

Both input and output is JSON payloads 


UDTF - userdefined table functions will be handled by http "GET" operations.
Input parameters will be query-string parameters. 


Scalar functions will be handled by http "GET" operations.
Input parameters will be query-string parameters. 

Note: Polymorphic procedures are not supported. noxDbAPI has no idea which implementation to use, so keep the schemas to only one implementation name pr. routine. 


Look in the example below or in ```/sql/examples.sql``` for a complete example-




## 1) Create the environment

Installation on your IBM i of `noxDbAPI` should be done with `git` which are available via `yum` - you can read more about [yum here](https://bitbucket.org/ibmi/opensource/src/master/docs/yum/).  

On your IBM i 

First `ssh` or  `call qp2term` into your IBM i, install git and clone this repo into the IFS:

```
yum install git
git -c http.sslVerify=false clone https://github.com/sitemule/noxDbAPI.git /prj/noxDbAPI
``` 

This will create a directory `/prj/noxDbAPI`

Now on a 5250 terminal:

```
GO ICEBREAK
ADDICESVR SVRID(noxDbAPI) HTTPPATH('/prj/noxdbAPI')  TEXT('Stored procedures, UDTF as webservices') SVRPORT(7007)                               
STRICESVR SVRID(noxDbAPI)
```


Compile the noxDbAPI router router code:

```
CRTICEPGM STMF('/prj/noxDbAPI/noxDbAPI.rpgle') SVRID(noxDbAPI)
````

### Enable noxDbAPI in your web config:

1) Add the noxDbAPI in the routing section in you webconfig.xml file in your server root:
2) Set the envvar NOXDBAPI_EXPOSE_SCHEMAS to the list of library / database schemas you will expose

```
<routing strict="false">
	<map pattern="^/noxdbAPI/" pgm="noxdbAPI" lib="*LIBL" />
</routing>

<envvar>
    <var name="NOXDBAPI_EXPOSE_SCHEMAS" value="NOXDBAPI,MICRODEMO"/> 
</envvar>

```


## 2) Using stored procedures: 


This example takes one input parameter and returns a dynamic result set. This is a perfect usecase for noxDbAPI. The comments we put on the procedure and parameters will be available in the openAPI (swagger) interface for documentation.  


Build a test stored procedure - paste this into ACS:

```
-- Procedure returns a resultset
--------------------------------
CREATE or REPLACE PROCEDURE  noxDbAPI.services_info_list  (
      in service_search_name  varchar(20) default null
)
LANGUAGE SQL 
DYNAMIC RESULT SETS 1

BEGIN

    declare c1 cursor with return for
    select * 
    from   qsys2.services_info
    where  service_search_name is null 
    or     upper(service_name) like '%' concat upper(service_search_name) concat '%';

    open c1;

END; 

comment on procedure noxDbAPI.services_info_list is 'Services info List';
comment on parameter noxDbAPI.services_info_list (service_search_name is 'Search services by name');

-- Test if the procedure works in ACS:

call noxDbAPI.services_info_list (service_search_name => 'ptf');
call noxDbAPI.services_info_list ();

``` 

## 3) Into action:

From your browser type the following, where `MY_IBM_I` is the name or TCP/IP address of your system: 
```
http://MY_IBM_I:7007/noxDbAp/
```

The first ```/noxDbAPI``` is the environment - the routing name, you can change that in the webconfig.xml "routing" tag


It will provide you with a openAPI interface for all stored procedures, UDTF and scalar function in the list you provide by the envvar ```NOXDBAPI_EXPOSE_SCHEMAS```

Be careful - newer expose more than required. i.e. never expose QSYS2. It is possible but never do this. 

Create a dedicated schema that will be used as web-services and simply expose one at the time. 




