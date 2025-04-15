/*  --------------------------------------------------------


    This is a cutesy SQL function to add user messages to 
    the response.
    
    It commuicates using environvariable, so it will not have any impact 
    for "other" clients using youer SQL procedures exposed by noxDbAPI 

    The environment variable MESSAGES_LIST wll be a JSON array, 
    and reset just before a SQL function of procedure is called
    noxDbApi 

    We just create it qusrsys for genereic access, but we sugges you 
    put it in your own application library

    -------------------------------------------------------- */



----------------------------------------------------------------
-- reads an environmentvariable, and if it does not exists
-- it returns a default value  
-- This uses inline C-functions, that only can be included 
----------------------------------------------------------------
call qusrsys.ifs_write('/tmp/include.c' , '
{
    #include <stdlib.h>
    char * env;
    
    ENVIRONMENT_VARIABLE_GET.ENVIRONMENT_VARIABLE.DAT[ENVIRONMENT_VARIABLE_GET.ENVIRONMENT_VARIABLE.LEN] =0;
    env = getenv(ENVIRONMENT_VARIABLE_GET.ENVIRONMENT_VARIABLE.DAT);
    if (env) {    
        MAIN.RES.LEN = strlen(env);
        memcpy ( MAIN.RES.DAT , env , MAIN.RES.LEN);
    } else {
        MAIN.RES.LEN = ENVIRONMENT_VARIABLE_GET.DEFAULT_VALUE.LEN;
        memcpy ( MAIN.RES.DAT , ENVIRONMENT_VARIABLE_GET.DEFAULT_VALUE.DAT , MAIN.RES.LEN);
    }
}       
');
create or replace function qusrsys.environment_variable_get (
    environment_variable  varchar(256),
    default_value         varchar(256) default ''
) 
returns  varchar(4095)
external action 
modifies sql data 
deterministic
set option output=*print, commit=*none, dbgview = *source --list
main:
begin
  
    declare res varchar(4096) default '';
    include '/tmp/include.c';
    return res;
  
end;

----------------------------------------------------------------
-- update or create an environmentvariable 
-- This uses inline C-functions, that only can be included 
----------------------------------------------------------------
call qsys2.ifs_write(
    path_name => '/tmp/include.c' , 
    file_ccsid => 1208, 
    overwrite => 'REPLACE',
    line =>'
{
    #include <stdlib.h>
    char env [32000];
    
    ENVIRONMENT_VARIABLE_SET.ENVIRONMENT_VARIABLE.DAT[ENVIRONMENT_VARIABLE_SET.ENVIRONMENT_VARIABLE.LEN] =0;
    ENVIRONMENT_VARIABLE_SET.ENVIRONMENT_VALUE.DAT[ENVIRONMENT_VARIABLE_SET.ENVIRONMENT_VALUE.LEN] =0;
    strcpy ( env, ENVIRONMENT_VARIABLE_SET.ENVIRONMENT_VARIABLE.DAT);
    strcat ( env , "="); 
    strcat ( env , ENVIRONMENT_VARIABLE_SET.ENVIRONMENT_VALUE.DAT);
    putenv ( env) ;
    
} 
');


create or replace procedure qusrsys.environment_variable_set (
    environment_variable  varchar(256),
    environment_value     varchar(32000)
) 
external action 
modifies sql data 
deterministic
set option output=*print, commit=*none, dbgview = *source --list
main:
begin
    include '/tmp/include.c';
end;

-- does it work:
call qusrsys.environment_variable_set ('TEST' , 'Some data');
values qusrsys.environment_variable_get ('TEST');

----------------------------------------------------------------
-- This procedure appends a message to 
-- the messages list environment variable 
----------------------------------------------------------------
create or replace function qusrsys.append_message  (
    message_text  varchar(512) default '',
    target        varchar(32) default ''
)
returns int
language sql
modifies sql data 
set option output=*print, commit=*none, dbgview = *source --list 
begin
 
    declare messages_list varchar(32000) default '';
    declare messages_object varchar(1024);

    set messages_object = '{"messageText":"'  || message_text || '","target":"' || target || '"}'; 

    set messages_list = qusrsys.environment_variable_get ('MESSAGES_LIST'); 

    if  messages_list = '' then 
        set messages_list = '[' || messages_object || ']';
    else 
        set messages_list = substr(messages_list , 1, length(messages_list) - 1) || ',' || messages_object || ']';
    end if; 

    call qusrsys.environment_variable_set ( 'MESSAGES_LIST' , messages_list);
    return 1; -- Done 
end;


-- Usecase
call   qusrsys.environment_variable_set ('MESSAGES_LIST' , ''); -- Clear the list 
values qusrsys.append_message ( 'Custommer 123 does not exists' , 'customer_number'); 
values qusrsys.append_message ( 'Item 789 does not exists' , 'item_number'); 
values qusrsys.environment_variable_get ('MESSAGES_LIST'); -- Show the list

