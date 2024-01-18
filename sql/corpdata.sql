/* --------------------------------------------------------


    This examples illustrates how to secure expose a scema
    using IBM corpdata sample database (corpdata) as data provider

    Here we uses the ANNOTATED settings in the webconfig
    that cause only routines with a @Method and @Endpoint 
    annotation will be exposed as services: 
    
    You have to set the webconfig like this:  
     
	<envvar>
		<var name="NOXDBAPI_EXPOSE_SCHEMAS" value="CORPDATA"/>
		<var name="NOXDBAPI_EXPOSE_ROUTINES" value="ANNOTATED"/>
	</envvar>

*/

-- First build the sample schema:

call qsys.create_sql_sample('CORPDATA');

-- We can then play with these;
select * from systables where table_schema= 'CORPDATA';
 
select * from corpdata.employee;


----------------------------------------------------------------
-- Example1: 
-- A stored procedure that returns exatly one dynamic result set
create or replace procedure  corpdata.employee_list  (
    in employee_search_name  varchar(20) default null
)
language sql
dynamic result sets 1
 
begin
 
    declare c1 cursor with return for
    select *
    from   corpdata.employee
    where  employee_search_name is null
    or     upper(firstnme concat ' '  concat lastname)  like '%' concat upper(employee_search_name) concat '%';
 
    open c1;
 
end;

-- The parameter description will be visible in the openAPI( swagger) user interface: 
comment on procedure corpdata.employee_list is 'Employee List @Method=GET @Endpoint=employees';
comment on parameter corpdata.employee_list (employee_search_name is 'Search Employee List by name');
 
-- Test if the procedure works in ACS:
call corpdata.employee_list (employee_search_name => 'john');
call corpdata.employee_list ();

---------------------------------------------------------------
-- Example2: 
-- UDTF - Userdefined table function that returns a table 
-- A stored procedure that returns exatly one dynamic result set
select * from corpdata.department;

create or replace function corpdata.department_list  (
    search_department_name  varchar(36) default null
)
returns table ( 
    department_id   character(3),
    department_name varchar(36),
    manager_number  character(6),
    administrating_department_id  character(3),
    department_location character(16)
)
language sql 

begin

    return 
        select 
            deptno,
            deptname,
            mgrno,
            admrdept,
            location
        from   corpdata.department
        where  search_department_name is null 
        or     upper(deptname) like upper(search_department_name) concat '%';

end; 

-- The parameter description will be visible in the openAPI( swagger) user interface: 
comment on function corpdata.department_list is 'Departments @Method=GET @Endpoint=departments';
comment on parameter function corpdata.department_list (search_department_name is 'Search departments by name');

select * from table( corpdata.department_list (search_department_name => 'branch'));
select * from table( corpdata.department_list ());

----------------------------------------------------------------------
-- Scalar function 
select * from corpdata.department;

create or replace function  corpdata.administrating_department_for_id  (
    department_ID  character(3)
)
returns character(3) 
language sql 
begin

    return (  
        select admrdept 
        from corpdata.department 
        where deptno = department_ID 
        limit 1
   );

end; 

-- The parameter description will be visible in the openAPI( swagger) user interface: 
comment on function corpdata.administrating_department_for_id is 'Returns the administration department id for an department id @Method=GET @Endpoint=departmentAdmin';
comment on parameter corpdata.administrating_department_for_id (department_ID is 'department ID');

-- Test if the procedure works in ACS:
values corpdata.administrating_department_for_id  ( department_ID => 'D01');
values corpdata.administrating_department_for_id  ( department_ID => 'XYZ'); -- error test: returns NULL



----------------------------------------------------------------------
-- Direct Call procedure, not here we join stuff together
    select *
    from   corpdata.employee;

create or replace procedure  corpdata.employee_info  (
    in  employee_id character(6),
    out first_name varchar(12),
    out midt_initials character(1),
    out last_name varchar(15),
    out work_department character(3),
    out department_name varchar(36)
)
language sql 

begin
    select
        firstnme,
        midinit,
        lastname,
        workdept,
        deptname
    into 
        first_name ,
        midt_initials ,
        last_name ,
        work_department ,
        department_Name 
    from   corpdata.employee
    left  join corpdata.department
        on employee.workdept =  department.deptno
    where  empno = employee_id;

end; 

-- The parameter description will be visible in the openAPI( swagger) user interface: 
comment on procedure corpdata.employee_info is 'Employee information @Method=GET @Endpoint=employeeInfo';
comment on parameter corpdata.employee_info (employee_id is 'Employee id');

-- Test if the procedure works in ACS:
call corpdata.employee_info ( 
  employee_id => '000050',
  first_name  => ?,
  midt_initials => ?,
  last_name => ?,
  work_department => ?,
  department_Name => ? 
);  



select *
from   corpdata.employee;

----------------------------------------------------------------------
-- Example 4:
-- Employee as a annotaded procedure 
----------------------------------------------------------------------
-- Procedure used for fetch on e row  

create or replace procedure  corpdata.employee_fetch  (
    in empno character(6) ,
    out firstnme varchar(12) ,
    out midinit character(1) ,
    out lastname varchar(15) ,
    out workdept character(3) ,
    out phoneno character(4) ,
    out hiredate date ,
    out job character(8) ,
    out edlevel smallint ,
    out sex character(1) ,
    out birthdate date ,
    out salary decimal(9, 2) ,
    out bonus decimal(9, 2) ,
    out comm decimal(9, 2 ) 
)
    language sql 
    no external action 
    set option output=*print, commit=*none, dbgview = *list

begin
    declare sqlcode int;
    declare message varchar(512);
    select
        empno,
        firstnme,
        midinit,
        lastname,
        workdept,
        phoneno,
        hiredate,
        job,
        edlevel,
        sex,
        birthdate,
        salary,
        bonus,
        comm
    into
        employee_fetch.empno,
        employee_fetch.firstnme,
        employee_fetch.midinit,
        employee_fetch.lastname,
        employee_fetch.workdept,
        employee_fetch.phoneno,
        employee_fetch.hiredate,
        employee_fetch.job,
        employee_fetch.edlevel,
        employee_fetch.sex,
        employee_fetch.birthdate,
        employee_fetch.salary,
        employee_fetch.bonus,
        employee_fetch.comm
    from  corpdata.employee a
    where empno = employee_fetch.empno;
    
    if  sqlcode <> 0 then
         -- The number of the state will be the http error returned: here 404 not found
        set message = 'Row does not exists for employee ' || empno;
        signal sqlstate 'HT404' set message_text = message;
    end if;

end;    

-- The annotation @Method in the description makes the procedure visible in the openAPI( swagger) user interface: 
-- The annotation @Endpoint is the name of the endpoint
comment on procedure corpdata.employee_fetch is 'Retrive Employee information @Method=GET @Endpoint=employee';

----------------------------------------------------------------------------------------------------
-- The procedure used for PATCH 
create or replace procedure  corpdata.employee_update  (
    in empno character(6) ,
    in firstnme varchar(12) ,
    in midinit character(1) ,
    in lastname varchar(15) ,
    in workdept character(3) ,
    in phoneno character(4) ,
    in hiredate date ,
    in job character(8) ,
    in edlevel smallint ,
    in sex character(1) ,
    in birthdate date ,
    in salary decimal(9, 2) ,
    in bonus decimal(9, 2) ,
    in comm decimal(9, 2 ) 
)
    language sql 
    no external action 
    set option output=*print, commit=*none, dbgview = *list

begin
    declare sqlcode int;
    declare message varchar(512);
    update corpdata.employee 
    set
        empno       = employee_update.empno,
        firstnme    = employee_update.firstnme,
        midinit     = employee_update.midinit,
        lastname    = employee_update.lastname,
        workdept    = employee_update.workdept,
        phoneno     = employee_update.phoneno,
        hiredate    = employee_update.hiredate,
        job         = employee_update.job,
        edlevel     = employee_update.edlevel,
        sex         = employee_update.sex,
        birthdate   = employee_update.birthdate,
        salary      = employee_update.salary,
        bonus       = employee_update.bonus,
        comm        = employee_update.comm
    where empno = employee_update.empno;
    
    if  sqlcode <> 0 then
        -- The number of the state will be the http error returned: here 404 not found
        set message = 'Row does not exists for employee ' || empno;
        signal sqlstate 'HT404' set message_text = message ;
    end if;
    
end;

-- The annotation @Method in the description makes the procedure visible in the openAPI( swagger) user interface:
-- The annotation @Endpoint is the name of the endpoint
comment on procedure corpdata.employee_update is 'Update Employee information @Method=PATCH @Endpoint=employee';



-- Test the two procedures for get and set:
call corpdata.employee_fetch ( 
    empno => '000050',
    firstnme => ?,
    midinit => ?,
    lastname => ?,
    workdept => ?,
    phoneno => ?,
    hiredate => ?,
    job => ?,
    edlevel => ?,
    sex => ?,
    birthdate => ?,
    salary => ?,
    bonus => ?,
    comm => ?
);  

call corpdata.employee_update ( 
    empno => '000050',
    firstnme => 'JOHN',
    midinit => 'B',
    lastname => 'GEYER',
    workdept => 'E01',
    phoneno => '6789',
    hiredate => '1949-08-17',
    job => 'MANAGER',
    edlevel => 17,
    sex => 'M',
    birthdate => '1925-09-15',
    salary => 40175.00,
    bonus => 800.00,
    comm => 3214.00
);  
-- does not exists
call corpdata.employee_fetch ( 
    empno => '999999',
    firstnme => ?,
    midinit => ?,
    lastname => ?,
    workdept => ?,
    phoneno => ?,
    hiredate => ?,
    job => ?,
    edlevel => ?,
    sex => ?,
    birthdate => ?,
    salary => ?,
    bonus => ?,
    comm => ?
);  


  

select *
from   corpdata.employee
where empno = '000050';
 
