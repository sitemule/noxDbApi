-- This examples uses IBM corpdata sample database (corpdata) as data provider
call qsys.create_sql_sample('CORPDATA');

-- We can then play with these;
select * from systables where table_schema= 'CORPDATA';
 

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
 
comment on procedure corpdata.employee_list is 'Employee List';
comment on parameter corpdata.employee_list (employee_search_name is 'Search Employee List by name');
 
-- Test if the procedure works in ACS:
call corpdata.employee_list (employee_search_name => 'john');
call corpdata.employee_list ();

----------------------------------------------------------------
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

comment on function corpdata.department_list is 'Departments';
comment on parameter function corpdata.department_list (search_department_name is 'Search departments by name');

select * from table( corpdata.department_list (search_department_name => 'branch'));
select * from table( corpdata.department_list ());

----------------------------------------------------------------------
-- Scalar function 
select * from corpdata.department;

create or replace function  corpdata.administrating_department_for_id  (
    department_ID  CHARACTER(3)
)
returns CHARACTER(3) 
language sql 
begin

    return (  
        select admrdept 
        from corpdata.department 
        where deptno = department_ID 
        limit 1
   );

end; 

comment on function corpdata.administrating_department_for_id is 'Returns the administration department id for an department id ';
comment on parameter corpdata.administrating_department_for_id (department_ID is 'department ID');

-- Test if the procedure works in ACS:
values corpdata.administrating_department_for_id  ( department_ID => 'D01');
values corpdata.administrating_department_for_id  ( department_ID => 'XYZ');

 


----------------------------------------------------------------------
-- Direct Call procedure
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

comment on procedure corpdata.employee_info is 'Employee information';
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


 
