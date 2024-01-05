-- This examples uses IBM corpdata sample database (corpdata) as data provider
call qsys.create_sql_sample('CORPDATA');

-- We can then play with these;
select * from systables where table_schema= 'CORPDATA';
 
     select *
    from   corpdata.employee;


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
comment on procedure corpdata.employee_list is 'Employee List';
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
comment on function corpdata.department_list is 'Departments';
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
comment on function corpdata.administrating_department_for_id is 'Returns the administration department id for an department id ';
comment on parameter corpdata.administrating_department_for_id (department_ID is 'department ID');

-- Test if the procedure works in ACS:
values corpdata.administrating_department_for_id  ( department_ID => 'D01');
values corpdata.administrating_department_for_id  ( department_ID => 'XYZ'); -- error test: returns NULL



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

-- The parameter description will be visible in the openAPI( swagger) user interface: 
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



select *
from   corpdata.employee;

----------------------------------------------------------------------
-- Example 4:
-- Employee as a annotaded procedure 
----------------------------------------------------------------------
-- Procedure used for GET 

create or replace procedure  corpdata.employee_get  (
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
        employee_get.empno,
        employee_get.firstnme,
        employee_get.midinit,
        employee_get.lastname,
        employee_get.workdept,
        employee_get.phoneno,
        employee_get.hiredate,
        employee_get.job,
        employee_get.edlevel,
        employee_get.sex,
        employee_get.birthdate,
        employee_get.salary,
        employee_get.bonus,
        employee_get.comm
    from  corpdata.employee a
    where empno = employee_get.empno;
    
    if  sqlcode <> 0 then
        set message = 'Row does not exists for employee ' || empno;
        signal sqlstate 'USR01' set message_text = message , column_name = 'empno';
    end if;

end;    

-- The annotation @Method in the description makes the prcdure visible in the openAPI( swagger) user interface: 
-- The annotation @Endpoint is the name of the endpoint
comment on procedure corpdata.employee_get is 'Retrive Employee information @Method=GET @Endpoint=employee';

----------------------------------------------------------------------------------------------------
-- The procedure used for PATCH 
create or replace procedure  corpdata.employee_set  (
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
        empno       = employee_set.empno,
        firstnme    = employee_set.firstnme,
        midinit     = employee_set.midinit,
        lastname    = employee_set.lastname,
        workdept    = employee_set.workdept,
        phoneno     = employee_set.phoneno,
        hiredate    = employee_set.hiredate,
        job         = employee_set.job,
        edlevel     = employee_set.edlevel,
        sex         = employee_set.sex,
        birthdate   = employee_set.birthdate,
        salary      = employee_set.salary,
        bonus       = employee_set.bonus,
        comm        = employee_set.comm
    where empno = employee_set.empno;
    
    if  sqlcode <> 0 then
        set message = 'Row does not exists for employee ' || empno;
        signal sqlstate 'USR01' set message_text = message , column_name = 'empno';
    end if;
    
end;    

-- The annotation @Method in the description makes the prcdure visible in the openAPI( swagger) user interface: 
-- The annotation @Endpoint is the name of the endpoint
comment on procedure corpdata.employee_set is 'Update Employee information @Method=PATCH @Endpoint=employee';



-- Test the two procedures for get and set:
call corpdata.employee_get ( 
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

call corpdata.employee_set ( 
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
call corpdata.employee_get ( 
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
 
