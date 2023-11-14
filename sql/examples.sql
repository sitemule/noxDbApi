--drop  procedure  noxDbApi.services_info_list;

create or replace procedure  noxDbApi.services_info_list  (
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

comment on procedure noxDbApi.services_info_list is 'Services info List';
comment on parameter noxDbApi.services_info_list (service_search_name is 'Search services by name');

-- Test if the procedure works in ACS:

call noxDbApi.services_info_list (service_search_name => 'ptf');
call noxDbApi.services_info_list ();

---------------------------------------------------------------
-- UDTF 
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

comment on function noxDbApi.services_info_categories is 'Services info Categories';
comment on parameter function noxDbApi.services_info_categories (search_category is 'Search service category by name');

select * from table( noxDbApi.services_info_categories (search_category => 'work'));
select * from table( noxDbApi.services_info_categories ());

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

comment on function noxDbApi.divide is 'Divide two numbers and return the result ';
comment on parameter noxDbApi.divide (dividend is 'Dividend');
comment on parameter noxDbApi.divide (divisor is 'Divisor');

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





