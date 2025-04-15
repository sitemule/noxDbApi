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

    The crud examples - showcases the CREAD, READ, UPDATE, DELETE and search
*/

-- First build the sample schema:
call qsys.create_sql_sample('CORPDATA');
 
-- This is the table we want to do CRUD upon: 
select * from corpdata.employee;

-- The READ, implements both the search and get row by empno exposing the dual http GET method
create or replace function corpdata.employee_fetch   (
    empno character(6) default null,
    search_employee_name  varchar(12) default null
)
returns table ( 
    empno       character(6),
    firstnme    varchar(12),
    midinit     character(1),
    lastname    varchar(15),
    workdept    character(3),
    phoneno     character(4),
    hiredate    date,
    job         character(8),
    edlevel     smallint,
    sex         character(1),
    birthdate   date,
    salary      decimal(9, 2),
    bonus       decimal(9, 2),
    comm        decimal(9, 2)
)
    language sql 
    no external action 
    set option output=*print, commit=*none, dbgview = *list
begin

    declare sqlcode int;

    if search_employee_name is null and  empno is null then
        -- The number of the state will be the http error returned: here 406 Not Acceptable
        signal sqlstate 'HT406' set message_text = 'One of the input arguments has to be provided';
    end if;

    return 
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
        from   corpdata.employee
        where  (upper(firstnme || ' ' || lastname) like upper('%' || search_employee_name || '%'))
        or     (empno = employee_fetch.empno); 

end; 

-- The parameter description will be visible in the openAPI( swagger) user interface: 
-- The annotation @Method in the description makes the procedure visible in the openAPI( swagger) user interface:
-- The annotation @Endpoint is the name of the endpoint
-- The annotation @Location describes whe the parameter is found: 
--  PATH=In the path comma number of the url next to the endpoint. 
--  QUERY=Query string parameter
--  FORM=In the form  
--  BODY=In the JSON payload

comment on function corpdata.employee_fetch  is 'Read an employee or search for employees @Method=GET @Endpoint=employee';
comment on parameter function corpdata.employee_fetch  (empno is 'Unique employee ID @Location=PATH,1');
comment on parameter function corpdata.employee_fetch  (search_employee_name is 'Search for employees by name or get one specific row');

select * from table( corpdata.employee_fetch  (search_employee_name => 'john'));
select * from table( corpdata.employee_fetch  (search_employee_name => '')); -- list all 
select * from table( corpdata.employee_fetch  (empno => '000050'));
select * from table( corpdata.employee_fetch  ()); -- No parameters - return exeption


----------------------------------------------------------------------------------------------------
-- The procedure used for PUT
create or replace procedure  corpdata.employee_update  (
    in empno        character(6) ,
    in firstnme     varchar(12) ,
    in midinit      character(1) ,
    in lastname     varchar(15) ,
    in workdept     character(3) ,
    in phoneno      character(4) ,
    in hiredate     date ,
    in job          character(8) ,
    in edlevel      smallint ,
    in sex          character(1) ,
    in birthdate    date ,
    in salary       decimal(9, 2) ,
    in bonus        decimal(9, 2) ,
    in comm         decimal(9, 2 ) 
)
    language sql 
    no external action 
    set option output=*print, commit=*none, dbgview = *list

begin
    declare sqlcode int;
    declare err int default 0;
    declare message varchar(512);
    
    -- validate the input
    if ifnull(employee_update.empno, '') = '' then  
        set err = qusrsys.append_message ( 'Employee number has to be given' , 'empno'); 
    end if;

    if sex not in ('F', 'M') then 
        set err = qusrsys.append_message ( 'Employee sex must be F or M ' , 'sex'); 
    end if;
    
    -- If just one err occurs, we termiante this procedure with a final message
    -- The number of the state will be the http error returned: here 406 Not Acceptable
    if err > 0 then 
        signal sqlstate 'HT406' set message_text = 'Input arguments are not valid. Examinate details';
    end if;
    
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
        set err = qusrsys.append_message ( 'Employee number ' || employee_update.empno || ' does not exists' , 'empno'); 
        -- The number of the state will be the http error returned: here 404 not found 
        signal sqlstate 'HT404' set message_text = 'Employee not found';
    end if;
    
end;

-- The annotation @Method in the description makes the procedure visible in the openAPI( swagger) user interface:
-- The annotation @Endpoint is the name of the endpoint
comment on procedure corpdata.employee_update is 'Update Employee information @Method=PUT @Endpoint=employee';
comment on parameter procedure corpdata.employee_update  (empno is 'Unique employee ID @Location=PATH,1');




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



----------------------------------------------------------------------------------------------------
-- The procedure used for POST - insert new row 
create or replace procedure  corpdata.employee_insert  (
    in empno        character(6) ,
    in firstnme     varchar(12) ,
    in midinit      character(1) ,
    in lastname     varchar(15) ,
    in workdept     character(3) ,
    in phoneno      character(4) ,
    in hiredate     date ,
    in job          character(8) ,
    in edlevel      smallint ,
    in sex          character(1) ,
    in birthdate    date ,
    in salary       decimal(9, 2) ,
    in bonus        decimal(9, 2) ,
    in comm         decimal(9, 2 ) 
)
    language sql 
    no external action 
    set option output=*print, commit=*none, dbgview = *list

begin
    declare sqlcode int;
    declare err int default 0;
    declare message varchar(512);
    
    -- validate the input
    if ifnull(employee_insert.empno, '') = '' then  
        set err = qusrsys.append_message ( 'Employee number has to be given' , 'empno'); 
    end if;

    if sex not in ('F', 'M') then 
        set err = qusrsys.append_message ( 'Employee sex must be F or M ' , 'sex'); 
    end if;
    
    -- If just one err occurs, we termiante this procedure with a final message
    -- The number of the state will be the http error returned: here 406 Not Acceptable
    if err > 0 then 
        signal sqlstate 'HT406' set message_text = 'Input arguments are not valid. Examinate details';
    end if;
    
    insert into  corpdata.employee
    (
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
     ) 
    values ( 
       employee_insert.empno,
       employee_insert.firstnme,
       employee_insert.midinit,
       employee_insert.lastname,
       employee_insert.workdept,
       employee_insert.phoneno,
       employee_insert.hiredate,
       employee_insert.job,
       employee_insert.edlevel,
       employee_insert.sex,
       employee_insert.birthdate,
       employee_insert.salary,
       employee_insert.bonus,
       employee_insert.comm
    );
    
    if  sqlcode <> 0 then
        set err = qusrsys.append_message ( 'Employee number ' || employee_insert.empno || ' could not be addsd' , 'empno'); 
        -- The number of the state will be the http error returned: here 405 - parameter error  
        signal sqlstate 'HT405' set message_text = 'Employee not added ';
    end if;
    
end;

-- The annotation @Method in the description makes the procedure visible in the openAPI( swagger) user interface:
-- The annotation @Endpoint is the name of the endpoint
comment on procedure corpdata.employee_insert is 'Insert Employee information @Method=POST @Endpoint=employee';



call corpdata.employee_insert ( 
    empno => '999999',
    firstnme => 'JOHN',
    midinit => 'X',
    lastname => 'MAXER',
    workdept => 'E01',
    phoneno => '9999',
    hiredate => '2024-02-16',
    job => 'MANAGER',
    edlevel => 20,
    sex => 'M',
    birthdate => '1964-02-16',
    salary => 8888.00,
    bonus => 800.00,
    comm => 3214.00
);  

-- here the deatil messages:
values qusrsys.environment_variable_get ('MESSAGES_LIST'); -- Show the list

----------------------------------------------------------------------------------------------------
-- The DELETE, implements the delete row by empno exposing the dual http DELETE method
create or replace function corpdata.employee_delete   (
    empno character(6)
)
returns int 
    language sql 
    modifies sql data
    no external action 
    set option output=*print, commit=*none, dbgview = *list
begin

    declare sqlcode int;
    declare err int default 0;


    if  empno is null then
        -- The number of the state will be the http error returned: here 406 Not Acceptable
        signal sqlstate 'HT406' set message_text = 'Emplyee number misssing';
    end if;

    delete from corpdata.employee
    where  (empno = employee_delete.empno); 
    
     if  sqlcode <> 0 then
        set err = qusrsys.append_message ( 'Employee number ' || employee_delete.empno || ' could not be deleted ' , 'empno'); 
        -- The number of the state will be the http error returned: here 405 - parameter error  
        signal sqlstate 'HT404' set message_text = 'Employee not deleted';
    end if;

    return 0;

end; 

-- The parameter description will be visible in the openAPI( swagger) user interface: 
-- The annotation @Method in the description makes the procedure visible in the openAPI( swagger) user interface:
-- The annotation @Endpoint is the name of the endpoint
-- The annotation @Location describes whe the parameter is found: 
--  PATH=In the path comma number of the url next to the endpoint. 
--  QUERY=Query string parameter
--  FORM=In the form  
--  BODY=In the JSON payload

comment on function corpdata.employee_delete  is 'Delete an employee  @Method=DELETE @Endpoint=employee';
comment on parameter function corpdata.employee_delete  (empno is 'Unique employee ID @Location=PATH,1');

values corpdata.employee_delete  (empno => '999999');


