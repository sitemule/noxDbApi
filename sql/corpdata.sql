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



----------------------------------------------------------------------
-- Example 4:
-- Employee as a CRUD procedure 
----------------------------------------------------------------------
    select *
    from   corpdata.employee;

create or replace procedure  corpdata.employee_crud  (
    in method varchar(10) default 'GET',  
    inout empno character(6) default null,
    inout firstnme varchar(12) default null,
    inout midinit character(1) default null,
    inout lastname varchar(15) default null,
    inout workdept character(3) default null,
    inout phoneno character(4) default null,
    inout hiredate date default null,
    inout job character(8) default null,
    inout edlevel smallint default null,
    inout sex character(1) default null,
    inout birthdate date default null,
    inout salary decimal(9, 2) default null,
    inout bonus decimal(9, 2) default null,
    inout comm decimal(9, 2 ) default null
)
    language sql 
    specific emplcrud
    no external action 
    set option output=*print, commit=*none, dbgview = *list

begin
    declare sqlcode int;
    declare message varchar(512);
    case
        when method = 'GET' then
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
                employee_crud.empno,
                employee_crud.firstnme,
                employee_crud.midinit,
                employee_crud.lastname,
                employee_crud.workdept,
                employee_crud.phoneno,
                employee_crud.hiredate,
                employee_crud.job,
                employee_crud.edlevel,
                employee_crud.sex,
                employee_crud.birthdate,
                employee_crud.salary,
                employee_crud.bonus,
                employee_crud.comm
            from  corpdata.employee a
            where empno = employee_crud.empno;
            
            if  sqlcode <> 0 then
                signal sqlstate 'USR01' set message_text = 'Row does not exists ' , column_name = 'empno';
            end if;



        when method = 'PATCH' then
            update corpdata.employee 
            set
                empno       = employee_crud.empno,
                firstnme    = employee_crud.firstnme,
                midinit     = employee_crud.midinit,
                lastname    = employee_crud.lastname,
                workdept    = employee_crud.workdept,
                phoneno     = employee_crud.phoneno,
                hiredate    = employee_crud.hiredate,
                job         = employee_crud.job,
                edlevel     = employee_crud.edlevel,
                sex         = employee_crud.sex,
                birthdate   = employee_crud.birthdate,
                salary      = employee_crud.salary,
                bonus       = employee_crud.bonus,
                comm        = employee_crud.comm
            where empno = employee_crud.empno;
           
            if  sqlcode <> 0 then
                signal sqlstate 'USR01' set message_text = 'Row not updated' , column_name = 'empno';
            end if;
           
        else
            set message = 'Method ' concat  method concat  ' is not supported';
            signal sqlstate 'USR01' set message_text = message , column_name = 'method';
     end case;
end;    

-- The parameter description will be visible in the openAPI( swagger) user interface: 
comment on procedure corpdata.employee_crud is 'Employee CRUD information';

-- The 'methods=' causes noxDbApi to expose these methods in openAPI / Swagger 
-- Also - pass this parameter (what ever name) with the HTTP method used.
-- Also - leave the parameter out from the openAPI / Swagger definition  
comment on parameter corpdata.employee_crud.method is 'methods=GET,PATCH';



-- This willl silently use the GET method in the CRUD procedure:
call corpdata.employee_crud ( 
    method => 'GET',
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

call corpdata.employee_crud ( 
    method => 'PATCH',
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
call corpdata.employee_crud ( 
    method => 'GET',
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


-- POST is not suppported 
call corpdata.employee_crud ( 
    method => 'POST',
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

    select *
    from   corpdata.employee
    where empno = '000050';
 
