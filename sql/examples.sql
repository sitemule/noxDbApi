-- example 1: Simple as possible - create a view as a service:
-- Note: The view is a "read only" so it will automaticall expose a GET method
-------------------------------------------------------------------------------
drop view noxdbapi.services_info_view;
create or replace view  noxdbapi.services_info_view as
    select * from qsys2.services_info;

comment on table  noxDbApi.services_info_view is 'Services info view @Endpoint=servicesInfoView';
comment on column noxDbApi.services_info_view.service_name  is 'Search services by name @Location=PATH,1';

select * from sysviews where table_schema = 'NOXDBAPI';

-- example 2: create a CRUD view as a service:
-- Note: The view is a "read only" so it will automaticall expose a GET method
--drop view noxdbapi.customer_view
-------------------------------------------------------------------------------
create or replace view  noxdbapi.customer_view as
    select * from qiws.QCUSTCDT; 

select * from noxdbapi.customer_view;
comment on table  noxDbApi.customer_view is 'Customer view service @Endpoint=customerView';
comment on column noxDbApi.customer_view.cusnum  is 'Customer ID @Location=PATH,1';

---------------------------------------------------------------
-- example 3: UDTF userdefined table funciton 
--drop function noxDbApi.services_info_categories;
create or replace function noxDbApi.services_info_categories  (
    search_category varchar(20) default null
)
returns table ( 
   category_name varchar(32),
   number_of_services int
)
language sql 

begin

    declare method varchar(20); 

    return 
        select service_category , count(*) 
        from   qsys2.services_info
        where  search_category is null 
        or     upper(service_category) like upper(search_category) concat '%'
        group by service_category;

end; 

comment on function noxDbApi.services_info_categories is 'Services info Categories UDTF @Endpoint=servicesInfoCategories';
comment on parameter function noxDbApi.services_info_categories (search_category is 'Search service category by name @Location=PATH,1');

select * from table( noxDbApi.services_info_categories (search_category => 'work'));
select * from table( noxDbApi.services_info_categories ());

select * from qsys2.sysroutines where specific_schema = 'NOXDBAPI';  
drop specific routine  noxdbapi.services_info_categories;



-------------------------------------------------------------------------------
-- example 4: Procedure as as service
create or replace procedure  noxDbApi.services_info_proc  (
    in service_search_name  varchar(20) default null
)
language sql 
dynamic result sets 1


begin

    declare c1 cursor with return for
    select * 
    from   qsys2.services_info
    where  service_search_name is null 
    or     upper(service_name) like '%' concat upper(service_search_name) concat '%';

    open c1;

end; 

comment on procedure noxDbApi.services_info_proc is 'Services info procedure @Method=GET @Endpoint=servicesInfoProcedure';
comment on parameter noxDbApi.services_info_proc (service_search_name is 'Search services by name @Location=PATH,1');

-- Test if the procedure works in ACS:

call noxDbApi.services_info_proc (service_search_name => 'ptf');
call noxDbApi.services_info_proc ();

select * from qsys2.sysroutines where specific_schema = 'NOXDBAPI';  
drop specific routine  noxdbapi.SERVICES_INFO_PROC;

----------------------------------------------------------------------
-- Scalar function 
-- Note: This can be used to test errors: Divide by zero 
create or replace function  noxDbApi.divide  (
    dividend  float ,
    divisor   float 
)
returns float
language sql 
begin

    return dividend / divisor;

end; 

comment on function noxDbApi.divide is 'Divide two numbers and return the result @Method=POST @Endpoint=divide';
comment on parameter noxDbApi.divide (dividend is 'Dividend @Location=QUERY');
comment on parameter noxDbApi.divide (divisor is 'Divisor @Location=QUERY');

-- Test if the procedure works in ACS:
values noxDbApi.divide ( dividend => 100 , divisor => 10);
values noxDbApi.divide ( dividend => 1   , divisor => 3 );
values noxDbApi.divide ( dividend => 1   , divisor => 0 ); -- Fails of cause


select * from qsys2.sysroutines where routine_schema = 'NOXDBAPI';

 
 


----------------------------------------------------------------------
-- Direct Call procedure
create or replace procedure  noxDbApi.concat_text  (
    in text1  varchar(256),
    in text2  varchar(256),
    out result_text varchar (256)
)
language sql 

begin

    set result_text = text1 concat ' ' concat text2;

end; 

comment on procedure noxDbApi.concat_text is 'Concatenate two strings including a blank';
comment on parameter noxDbApi.concat_text (text1 is 'First input text');
comment on parameter noxDbApi.concat_text (text2 is 'Second input text');
comment on parameter noxDbApi.concat_text (result_text is 'Result output');

-- Test if the procedure works in ACS:
call noxDbApi.concat_text ( 
  text1 => 'Niels',
  text2 => 'Liisberg',
  result_text => ?
);  

------------------------------------------------
create or replace procedure  noxDbApi.list_customer  (
    in search_name  varchar(20) default null
)
language sql 
dynamic result sets 1


begin

    declare c1 cursor with return for
    select * 
    from   qiws.QCUSTCDT
    where  search_name is null 
    or     upper(LSTNAM) like '%' concat upper(search_name) concat '%';

    open c1;

end; 

comment on procedure noxDbApi.list_customer is 'List customers';
comment on parameter noxDbApi.list_customer (search_name is 'Search by name');

call noxDbApi.list_customer ();





