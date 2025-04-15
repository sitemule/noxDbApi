<%@ free="*YES" language="SQLRPGLE" owner="QPGMR"%>
<%
ctl-opt copyright('System & Method (C), 2019-2025');
ctl-opt decEdit('0,') datEdit(*YMD.) main(main); 
ctl-opt bndDir('NOXDB':'ICEUTILITY');

/* -----------------------------------------------------------------------------
	Service . . . : Service programs as service endpoints
	Author  . . . : Niels Liisberg 
	Company . . . : System & Method A/S
	

	noxPrcApi is a simple way to expose service program procedures as RESTservice. 
	Note - you might contain the services you expose either by access security
	or by user defined access rules added to this code - Whatever serves you best.

	

	1) Copy this code to your own server root and 
	compile this stored procedure router - Supply your file and serverid:

	CRTICEPGM STMF('/prj/noxdbapi/noxprcapi.rpgle') SVRID(noxdbapi)


	
	4) Enable noxPrcApi in your web config:
	
	Add the noxPrcApi in the routing section in you webconfig.xml file in your server root:

	<routing strict="false">
		<map pattern="^/noxPrcApi/" pgm="noxPrcApi" lib="*LIBL" />
	</routing>



	5) Load the openAPI / (swagger) interface for the noxPrcApi schema
	
	http://MY_IBM_I:7007/noxdbapi/




	By     Date       PTF     Description
	------ ---------- ------- ---------------------------------------------------
	NLI    13.04.2025         New program
	----------------------------------------------------------------------------- */
 /include qasphdr,jsonparser
 /include qasphdr,iceutility

// --------------------------------------------------------------------
// Main line:
// --------------------------------------------------------------------
dcl-proc main;

	dcl-s url  			varchar(256);
	dcl-s environment   varchar(64);
	dcl-s schemaName    varchar(64);
	dcl-s procName 		varchar(128);
 	
	if getServerVar('REQUEST_METHOD') = 'OPTIONS';
		setStatus ('200 Options are all wellcome');
		return;
	endif;

	url = getServerVar('REQUEST_FULL_PATH');
	environment = strLower(word (url:1:'/'));
	schemaName  = word (url:2:'/');
	procName    = word (url:3:'/');		

	if  schemaName = 'openapi-meta';
		// The envvar is set in the "webconfig.xml" file. The "envvar" tag
		serveListSchemaProcs (
			environment : 
			getenvvar('NOXDBAPI_EXPOSE_SCHEMAS') : 
			getenvvar('NOXDBAPI_EXPOSE_ROUTINES'):
			getenvvar('NOXDBAPI_EXPOSE_VIEWS')			
		); 
	elseif schemaName = 'static_resources' or procName = ''; 
		serveStatic (environment : schemaName : url);
	else;
		serveProcedureResponse (
			environment : 
			schemaName : 
			procName : 
			url : 
			getenvvar('NOXDBAPI_EXPOSE_SCHEMAS') : 
			getenvvar('NOXDBAPI_EXPOSE_ROUTINES'):
			getenvvar('NOXDBAPI_EXPOSE_VIEWS')	
		);
	endif; 


end-proc;
// --------------------------------------------------------------------  
dcl-proc serveStatic;

	dcl-pi *n;
		environment varchar(64);
		schemaName varchar(64);
		url varchar(256);
	end-pi;

	dcl-s i	int(10);
	dcl-s fileName varchar(256); 
	dcl-s staticPath   varchar(256); 
	dcl-s pResponse	pointer;
	
	staticPath  = strLower(getServerVar('SERVER_ROOT_PATH') + '/static');

	if  %len(url)  = %len(environment);
		redirect (environment + '/');
		return;
	elseif  %len(url)  = %len(environment + '/');
		fileName = staticPath + '/swagger/index.html'; 
	else;		
		// count the slashes ( aka the +2 )
		fileName = %subst (url : 2 + %len(environment) );
		if  fileName = 'swagger-initializer.js';
			fileName = staticPath  + '/' + fileName; 
		else;
			fileName = staticPath  + '/swagger/' + fileName; 
		endif;
	endif;

	consoleLog (fileName);

	SetCharset ('charset=utf-8');
	if ResponseServeFile (fileName);
		setStatus ('404 ' + fileName + ' is missing');
	endif;

end-proc;

// --------------------------------------------------------------------  
dcl-proc serveProcedureResponse ;	

	dcl-pi *n;
		environment     varchar(64);
		schema          varchar(64);
		procName        varchar(128);
		url             varchar(256);
		exposeSchemas   varchar(256) const options(*varsize);
		exposeRoutines  varchar(256) const options(*varsize);
		exposeViews     varchar(256) const options(*varsize);
	end-pi;

	dcl-s pResponse		pointer;		
	dcl-s msg 			varchar(512);	
	dcl-s pPayload      pointer;	
	dcl-s name  		varchar(64);
	dcl-s value  		varchar(32760);
	dcl-s pathParm      varchar(256);
	dcl-s parmList  	varchar(32760);
	dcl-s sqlStmt   	varchar(32760);
	dcl-s sep       	varchar(16);
	dcl-s method        varchar(10);
	dcl-s specificName  varchar(128);
	dcl-s viewName 		varchar(128);
	dcl-s where  		varchar(256);
	dcl-s pRoutineMeta  pointer;
	dcl-s len 			int(10);
	dcl-s parmNum    	int(10);
	dcl-s err			ind;	
	dcl-ds iterParms  	likeds(json_iterator);
	dcl-ds iterList  	likeds(json_iterator);  
	
	SetContentType ('application/json;charset=UTF-8');

	if schema <= '';
		pResponse = FormatError (
			'Need schema and procedure'
		);
		return;
	endif;

	if wordIxNoCase (exposeSchemas : schema :',') <= 0;
		pResponse = FormatError (
			'Invalid schema ' + schema
		);
		return;
	endif;

	pPayload = json_ParseRequest();

	// When payload is not posted ( aka not a object) we create it from the url parameters
	// Ensure it is empty by creating a new. It can either be null of an empty object {}
	if json_getChild (pPayload) = *NULL; 
		json_delete(pPayload);
		pPayload = json_newObject();
	else; 
		iterList = json_setIterator(pPayload);  
		dow json_ForEach(iterList) ;  
			json_noderename (iterList.this : camelToSnakeCase ( json_getname (iterList.this) ));
		enddo; 
	endif;

	// append or replace querystring parameters to payload object 
	getQryStrList ( name : value : '*FIRST');
	dow name > '';
		json_setValue (pPayload : camelToSnakeCase(name) : value );
		getQryStrList ( name : value : '*NEXT');
	enddo;

	// First - do we have is as a view? 
	if exposeViews = 'ANNOTATED';
		viewName = getViewByAnnotations ( schema : procName) ;
	else; 
		viewName = '';
	endif;


	// First - do we have is as a view? 
	if viewName > ''; 

		
		sep = ' where ';
		for parmNum = 1 to 10;
			pathParm = word ( url: parmNum + 3: '/'); // TODO !! now  path parms start after the endpoint ( word 4 ..) , that will change!!
			if pathParm = '';
				leave;
			endif;
			where  += sep + getViewParmName ( schema : viewName : parmNum)
					+ ' = ' + strQuot(urlDecode(pathParm));
			sep = ' and ';
		endfor;

		method = getServerVar('REQUEST_METHOD');
		select;
			when method = 'GET';
				sqlStmt = 'select * from ' +  schema + '.' + viewName + where;
				pResponse = json_sqlResultSet (
					sqlStmt:
					1:            // Starting from row. TODO Paging 
					JSON_ALLROWS: // Number of rows to read. TODO Paging
					JSON_META + JSON_CAMEL_CASE + JSON_GRACEFUL_ERROR
				); 
				return;
			when method = 'PUT' and where > '';
				err = json_sqlUpdate (
					schema + '.' + viewName:
					pPayload:
					where
				);
				if err;
					pResponse = FormatError('Update error');
				else;
					pResponse = successTrue ();
				endif;
				return;
			when method = 'POST';
				err = json_sqlInsert (
					schema + '.' + viewName:
					pPayload
				);
				if err;
					pResponse = FormatError('Insert error');
				else;
					pResponse = successTrue ();
				endif;
				return;
			when method = 'DELETE' and where > '';
				err = json_sqlExec  (
					'delete from ' + schema + '.' + viewName + where
				);
				if err;
					pResponse = FormatError('Delete error');
				else;
					pResponse = successTrue ();
				endif;
				return;
		endsl; 

	endif;

	// path parameters given? find the name and add to the payload:
	if exposeRoutines = 'ANNOTATED';
		for parmNum = 1 to 10;
			pathParm = word ( url: parmNum + 3: '/'); // TODO !! now  path parms start after the endpoint ( word 4 ..) , that will change!!
			if pathParm = '';
				leave;
			endif;
			json_setValue (pPayload : getProcParmName ( schema : procName : parmNum) : pathParm );
		endfor;
	endif;	

	if exposeRoutines = 'ANNOTATED';
		specificName = getSpecificNameByAnnotations ( schema : procName) ;
	else;
		specificName = getSpecificName ( schema : procName) ;
	endif;

	pResponse = json_sqlExecuteRoutine (
		specificName : 
		pPayload : 
		JSON_META + JSON_CAMEL_CASE + JSON_GRACEFUL_ERROR:
		*ON // Specific 
	);

	// The result will be in snake ( as is). JSON is typically Cammel 
	// json_sqlExecuteRoutine is not supporting the JSON_CAMEL_CASE ( yet)  
	/* 	
	iterList = json_setIterator(pResponse);  
	dow json_ForEach(iterList) ;  
		json_noderename (iterList.this : snakeToCamelCase ( json_getname (iterList.this) ));
	enddo; 
	*/ 

	return;

on-exit; 

	renameResultRoot (pResponse : rootName());

	if   json_locate (pResponse : rootName()) <> *NULL
	and  (json_isnull (pResponse : rootName()) or json_getLength(json_locate(pResponse : rootName())) = 0);
		setStatus ('404');
		json_delete( pResponse);
		pResponse = FormatError('Row not found');
	elseif json_getstr(pResponse : 'success') = 'false';
		// backwards compatible - old noxdb call it msg and stmt:
		json_noderename ( json_locate ( pResponse:'msg'):'message');
		json_noderename ( json_locate ( pResponse:'stmt'):'description');
		msg = json_getstr(pResponse: 'message');
		setStatus ('406 ' + msg);
		consoleLogjson(pResponse);
	endif;

	responseWriteJson(pResponse);
	json_delete( pResponse);
	json_delete (pPayload);

end-proc;

// ------------------------------------------------------------------------------------
// get Specific Name by filter the name 
// ------------------------------------------------------------------------------------
dcl-proc getSpecificName;

	dcl-pi *n varchar(128);
		schema  varchar(64) value ;
		routine varchar(128) value ;
	end-pi;

	dcl-s functionType 	char(1);	
	dcl-s routineType 	char(10);	
	dcl-s specificName  varchar(128);

 	routine = strUpper(camelToSnakeCase (routine));
	schema  = strUpper(camelToSnakeCase (schema));

	if %subst(routine: %len(routine) - 4) = 'TABLE';
		functionType  = 'T';
		routineType  = 'FUNCTION';
		routine = %subst ( routine : 1: %len(routine) - 6);
	elseif %subst(routine: %len(routine) - 5) = 'SCALAR';
		functionType  = 'S';
		routineType  = 'FUNCTION';
		routine = %subst ( routine : 1: %len(routine) - 7);
	elseif %subst(routine: %len(routine) - 8) = 'PROCEDURE';
		functionType  = ' ';
		routine = %subst ( routine : 1: %len(routine) - 10);
		routineType  = 'PROCEDURE';
	else; 
		functionType  = '?';
		routine = '????';
	endif;

	exec sql 
		select specific_name  
		into   :specificName
		from   qsys2.sysroutines
		where  service_schema = :schema 
		and routine_type      = :routineType 
		and    service_name   = :routine
		and    function_type  = :functionType;


	return schema + '.' + specificName;
end-proc;
	
// ------------------------------------------------------------------------------------
// get Specific Name by annotations 
// ------------------------------------------------------------------------------------
dcl-proc getSpecificNameByAnnotations;

	dcl-pi *n varchar(128);
		schema  varchar(64) value ;
		routine varchar(128) value ;
	end-pi;

	dcl-s functionType 	char(1);	
	dcl-s routineType 	char(10);	
	dcl-s method  	    varchar(10);	
	dcl-s specificName  varchar(128);

	method = getServerVar('REQUEST_METHOD');
	schema = strUpper(camelToSnakeCase (schema));

	// Note: to make the endpoint unique:
	// 1) a blank has to follow the method name 
	// 2) The endpoint name has to terminate the textstring 
	exec sql 
		select specific_name  
		into   :specificName
		from   qsys2.sysroutines
		where  service_schema = :schema 
		and  ( long_comment not like '%@Method=%'   
		  or   long_comment like '%@Method=' || :method || '%')
		and  ( long_comment like '%@Endpoint=' || :routine  || ' %'
		  or   long_comment like '%@Endpoint=' || :routine  );

	return schema + '.' + specificName;
end-proc;
// ------------------------------------------------------------------------------------
// get name of the view by the anotation in systables  
// ------------------------------------------------------------------------------------
dcl-proc getViewByAnnotations;

	dcl-pi *n varchar(128);
		schema  varchar(64) value ;
		routine varchar(128) value ;
	end-pi;

	dcl-s functionType 	char(1);	
	dcl-s routineType 	char(10);	
	dcl-s method  	    varchar(10);	
	dcl-s viewName      varchar(128);

	method = getServerVar('REQUEST_METHOD');
	schema = strUpper(camelToSnakeCase (schema));

	// Note: to make the endpoint unique:
	// 1) a blank has to follow the method name 
	// 2) The endpoint name has to terminate the textstring 
	exec sql 
		select table_name 
		into   :viewName
		from qsys2.systables 
		where table_schema = :schema 
		and    ( long_comment like '%@Endpoint=' || :routine  || ' %'
		  or     long_comment like '%@Endpoint=' || :routine  );

	return %trimr(viewName);
end-proc;
// ------------------------------------------------------------------------------------
// get parameter name from a specific routing name by annotations 
// ------------------------------------------------------------------------------------
dcl-proc getProcParmName;

	dcl-pi *n varchar(128);
		schema  varchar(64) value ;
		routine varchar(128) value ;
		parmNumber  int(5) value;
	end-pi;

	dcl-s functionType 	char(1);	
	dcl-s routineType 	char(10);	
	dcl-s method  	    varchar(10);	
	dcl-s specificName  varchar(128);
	dcl-s parameterName varchar(128);
	dcl-s parmNumber_   varchar(3);

	method = getServerVar('REQUEST_METHOD');
	schema  = strUpper(camelToSnakeCase (schema));
	parmNumber_ = %char(parmNumber);

	// Note: to make the endpoint unique:
	// 1) a blank has to follow the method name 
	// 2) The endpoint name has to terminate the textstring 
	exec sql
		select parameter_name 
		into   :parameterName
		from   qsys2.sysroutines r
		join sysparms p 
			on (r.specific_schema , r.specific_name ) = (p.specific_schema ,p.specific_name)
		where  r.specific_schema = :schema 
		and  ( r.long_comment not like '%@Method=' 
			or r.long_comment like '%@Method=' || :method || '%') 
		and  ( r.long_comment like '%@Endpoint=' || :routine  || ' %'
		  or   r.long_comment like '%@Endpoint=' || :routine  )
        and    p.long_comment like '%@Location=PATH,' || :parmNumber_ || '%';
//        order by ordinal_position
//        limit 1 offset :parmNumber - 1; // Offset starts at 0 and we ask for parameter number starting at 1 


	return snakeToCamelCase (parameterName);
end-proc;
// ------------------------------------------------------------------------------------
// get parameter name from a specific routing name by annotations 
// ------------------------------------------------------------------------------------
dcl-proc getViewParmName;

	dcl-pi *n varchar(128);
		schema     varchar(64) value ;
		viewName   varchar(128) value ;
		parmNumber int(5) value;
	end-pi;

	dcl-s functionType 	char(1);	
	dcl-s routineType 	char(10);	
	//dcl-s method  	    varchar(10);	
	dcl-s specificName  varchar(128);
	dcl-s parameterName varchar(128);
	dcl-s parmNumber_   varchar(3);

	//method = getServerVar('REQUEST_METHOD');
	schema  = strUpper(camelToSnakeCase (schema));
	parmNumber_ = %char(parmNumber);

	// Note: to make the endpoint unique:
	// 1) a blank has to follow the method name 
	// 2) The endpoint name has to terminate the textstring 
	exec sql
		select column_name
		into   :parameterName
		from   qsys2.syscolumns 
		where  table_schema = :schema  
		and    table_name = :viewName
        and    long_comment like '%@Location=PATH,' || :parmNumber_ || '%';

	// return snakeToCamelCase (parameterName);
	return parameterName;
end-proc;
/* -------------------------------------------------------------------- *\ 
   JSON error monitor 
\* -------------------------------------------------------------------- */
dcl-proc FormatError;

	dcl-pi *n pointer;
		description  varchar(256) const options(*varsize);
	end-pi;                     

	dcl-s msg 					varchar(4096);
	dcl-s pMsg 					pointer;

	msg = json_message(*NULL);
	pMsg = json_parseString (' -
		{ -
			"success": false, - 
			"description":"' + description + '", -
			"message": "' + msg + '"-
		} -
	');

	consoleLog(msg);
	return pMsg;


end-proc;
/* -------------------------------------------------------------------- *\ 
   JSON error monitor 
\* -------------------------------------------------------------------- */
dcl-proc successTrue;

	dcl-pi *n pointer;
	end-pi;                     

	return json_parseString ('{"success":true}');

end-proc;

/* -------------------------------------------------------------------- *\ 
   produce JSON catalog
\* -------------------------------------------------------------------- */
dcl-proc serveListSchemaProcs;

	dcl-pi *n;
		environment 	varchar(64)  const options(*varsize);
		schemaNameList 	varchar(256) const options(*varsize);
		exposeRoutines  varchar(256) const options(*varsize);
		exposeViews     varchar(256) const options(*varsize);
	end-pi;

	dcl-s pRoutineGraph      	pointer; 
	dcl-s pSwagger     	pointer; 
	
	dcl-ds iterServicePgm  	likeds(json_iterator);
	dcl-ds iterParms  	    likeds(json_iterator);
	dcl-s  schemaList   varchar(256);

	dcl-s pParmObj      Pointer;
	dcl-s pParmArr      Pointer;
	
    dcl-s pMeta         Pointer;
	dcl-s h_i           int(10);
	Dcl-s pProcObj      Pointer;
	Dcl-S pProcArr      Pointer;
    dcl-s procNum	    int(10);
    dcl-s pPcmlProc	    pointer;
    
	pRoutineGraph = json_sqlResultSet (`
        select
            objlongschema  service_schema,                 
            objname        service_name,
            ifnull(objtext, '') long_comment
        from 
            table (qsys2.object_statistics(
                '${schemaNameList}','SRVPGM','*ALLSIMPLE')
            ) 
	`);

    iterServicePgm = json_setIterator(pRoutineGraph);  
    dow json_ForEach(iterServicePgm) ;  
        pMeta = json_ProcedureMeta (
            json_getStr(iterServicePgm.this: 'service_schema') : 
            json_getStr(iterServicePgm.this: 'service_name'):
            '*ALL'
        );

		// No metadata - do not expose it
		If pMeta = *NULL;
			json_delete(iterServicePgm.this);
			Iter;
		EndIf;
		
        json_writeXmlStmf(pMeta:'/prj/noxdbapi/debug/pcml.xml':1208:*off);

		pProcArr = json_newArray();
        procNum = json_getInt(pMeta:'pcml.program[UBOUND]');
		For h_i = 0 to procNum -1 ;
				
            pPcmlProc = json_locate(
                pMeta: 
                'pcml.program[' + %char(h_i) + ']'  
            ); 
			
            pProcObj = json_newObject();
            json_setStr(pProcObj :'name':json_getStr(pPcmlProc:'@entrypoint'));
            pParmArr = json_newArray();
            iterParms = json_setIterator(pPcmlProc);

            dow json_ForEach(iterParms);
                pParmObj = json_newObject();
                json_setStr(pParmObj :'name':json_getStr(iterParms.this:'@name'));
                json_setStr(pParmObj :'type':json_getStr(iterParms.this:'@type'));
                json_setInt(pParmObj :'length':json_getInt(iterParms.this:'@length'));
                json_setStr(pParmObj :'usage':json_getStr(iterParms.this:'@usage'));
                json_arrayPush(pParmArr:pParmObj);
            enddo;
            
            json_moveObjectInto(pProcObj :'parms':pParmArr);
			json_arrayPush(pProcArr:pProcObj);
		EndFor;
		json_moveObjectInto(iterServicePgm.this:'procedures':pProcArr);
    enddo; 

	renameResultRoot (pRoutineGraph : rootName());
    json_writeJsonStmf(pRoutineGraph:'/prj/noxdbapi/debug/routine-graph.json':1208);
	pSwagger = buildSwaggerJson (environment : pRoutineGraph);

	SetContentType ('application/json');
	responseWriteJson(pSwagger);

	json_delete (pRoutineGraph);
	json_delete (pSwagger);

end-proc;
// --------------------------------------------------------------------  
dcl-proc buildSwaggerJson;

	dcl-pi *n pointer;
		environment varchar(64) const options(*varsize);
		pRoutines pointer value;
	end-pi;

	dcl-ds iterServicePgm   likeds(json_iterator);  
	dcl-ds iterProcedures   likeds(json_iterator);  
	dcl-s pOpenApi  	    pointer;
	dcl-s pPaths  		    pointer;
	dcl-s pComponents 	    pointer;
	dcl-s pSchemas 	        pointer;
	dcl-s routinetype	    varchar(16);

	pOpenApi  =  openApiProlog();
	
	pPaths      = json_moveObjectInto  ( pOpenApi    : 'paths'      : json_newObject()); 
	pComponents = json_moveObjectInto  ( pOpenApi    : 'components' : json_newObject()); 
	pSchemas    = json_moveObjectInto  ( pComponents : 'schemas'    : json_newObject()); 

	// Now produce the openAPI JSON fro each routine 
	iterServicePgm = json_setIterator(pRoutines);  
	dow json_ForEach(iterServicePgm) ;  
        iterProcedures = json_setIterator(iterServicePgm.this: 'procedures');  
        dow json_ForEach(iterProcedures);  
            buildSwaggerForProcedure (
                snakeToCamelCase( environment): 
                iterProcedures.this : 
                pOpenApi
            );
        enddo;
	enddo;

	json_mergeObjects   ( pSchemas : definitions()  : MO_MERGE_NEW + MO_MERGE_MOVE); 
	json_moveObjectInto  ( pOpenApi  :  'externalDocs' : externalDocs() ); 

	return (pOpenApi);
end-proc;


// ------------------------------------------------------------------------------------
dcl-proc buildSwaggerForProcedure;

	dcl-pi *n;
		environment varchar(64) const options(*varsize);
		pRoutine 	pointer value;   
		pOpenApi 	pointer value;  
	end-pi;

	dcl-ds iterList   	  likeds(json_iterator);  
	dcl-ds iterParms   	  likeds(json_iterator);  
	dcl-ds iterPathParms  likeds(json_iterator);
	dcl-s pPaths  		  pointer;
	dcl-s pSchemas 	      pointer;
	dcl-s pParms  		  pointer;
	dcl-s pParm   		  pointer;
	dcl-s pMethod 		  pointer;
	dcl-s pPropertyInput  pointer;
	dcl-s pPropertyOutput pointer;
	dcl-s pParameters 	  pointer;
	dcl-s pParmsInput 	  pointer;
	dcl-s pParmsOutput 	  pointer;	
	dcl-s pRoute          pointer;
	dcl-s Schema   		  varchar(64);
	dcl-s Service         varchar(64);
	dcl-s Procedure       varchar(64);
	dcl-s RoutineType 	  varchar(10);
	dcl-s RoutineTypeNc   varchar(10);
	dcl-s resultSets      int(5);
	dcl-s methods         varchar(256);
	dcl-s method          varchar(16);
	dcl-s endpoint        varchar(256);
	dcl-s endpointPath    varchar(256);
	dcl-s pathName        varchar(256);
	dcl-s schemaOutput    varchar(256);
	dcl-s schemaInput     varchar(256);
	dcl-s schemaResponse  varchar(256);
	dcl-s schemaRequest   varchar(256);
	dcl-s pAnnotations    pointer;
	dcl-s description     varchar(1024);
	dcl-s pathParms		  int(5);
	dcl-s i				  int(5);	
	dcl-s j				  int(5);	
	dcl-s k				  int(5);	

    dcl-s pServicePgm	    pointer;
    dcl-s pProcedures       pointer;

    // Parent of me is "procedures" - Get the parent of that - which is the service program
    pProcedures = json_getParent (pRoutine);
    pServicePgm = json_getParent (pProcedures);

	pPaths  	= json_locate ( pOpenApi : 'paths');
	pSchemas 	= json_locate ( pOpenApi : 'components.schemas');

	schema      = json_getStr (pServicePgm:'service_schema');
	service     = json_getStr (pServicePgm:'service_name'); 
	description = json_getStr (pServicePgm:'long_comment');
	procedure 	= json_getStr (pRoutine   :'name'); 

    endpointPath = snakeToCamelCase(service) + '/' + NameCase (procedure);
    endpoint     = snakeToCamelCase(service) + NameCase (procedure);

	method = 'post';

	schemaInput    = endpoint + NameCase(method) + 'Input'  ;
	schemaOutput   = endpoint + NameCase(method) + 'Output' ;
	schemaRequest  = endpoint + NameCase(method) + 'Request'  ;
	schemaResponse = endpoint + NameCase(method) + 'Response' ;
	
	json_moveObjectInto  ( 
		pSchemas  :  
		schemaResponse : 
		buildResponseSchema (schemaOutput)
	); 

	pMethod = openApiMethod (
			schema:
			endpoint:
			description + ' - Procedure ':
			method:
			schemaInput: // "schemaRequest for complex types  !!
			schemaResponse 
		);

	pRoute = getRoute (pPaths : '/' + environment + '/' + schema + '/' + endpointPath );

	pParmsInput = json_moveObjectInto  ( pSchemas  :  schemaInput   : json_newObject() ); 
	json_setStr(pParmsInput : 'type' : 'object');
	pPropertyInput  = json_moveObjectInto  ( pParmsInput  :  'properties' : json_newObject() ); 

	pParmsOutput = json_moveObjectInto  ( pSchemas  :  schemaOutput   : json_newObject() ); 
	json_setStr(pParmsOutput : 'type' : 'object');
	pPropertyOutput  = json_moveObjectInto  ( pParmsOutput  :  'properties' : json_newObject() ); 


	iterParms = json_setIterator(pRoutine:'parms');  
	dow json_ForEach(iterParms) ;  
		if isInputInThisContext(iterParms.this : iterPathParms.this );
			json_nodeInsert ( pPropertyInput  : swaggerParm (iterParms.this)  : JSON_LAST_CHILD); 
		else;
			json_nodeInsert ( pPropertyOutput  : swaggerParm (iterParms.this)  : JSON_LAST_CHILD); 
		endif;
	enddo;

	json_moveObjectInto  ( pRoute  :  method  : pMethod ); 

end-proc;
// ------------------------------------------------------------------------------------
// getRoute
// ------------------------------------------------------------------------------------
dcl-proc getRoute;

	dcl-pi getRoute pointer ;
		pPaths pointer value;
		pathName varchar(256) const;
	end-pi;

	dcl-s pRoute	pointer;

	// When the endpoint exists - we just append each method
	pRoute = json_locate  ( pPaths : '"' + pathName +'"');
	if pRoute = *NULL; 
		pRoute = json_newObject();
		json_noderename (pRoute : pathName);
		json_nodeInsert ( pPaths  : pRoute : JSON_LAST_CHILD); 
	endif;

	return pRoute;
end-proc;

// ------------------------------------------------------------------------------------
// addPathParameters
// ------------------------------------------------------------------------------------
dcl-proc addPathParameters;

	dcl-pi addPathParameters pointer;
		pMethod  pointer value; 
		pRoutine pointer value; 
		length	 int(5)  value;
	end-pi;

	dcl-s counter int(5);	
	dcl-s str varchar(256);
	dcl-ds iterParms   	  likeds(json_iterator);  
	dcl-s location char(10);
	dcl-s pParameters   pointer;
	
	pParameters = json_newArray(); 

	iterParms = json_setIterator(pRoutine:'parms');  
	dow json_ForEach(iterParms) and counter < length; 
		location = json_getStr(iterParms.this: 'annotations.location'); 
		if 	%subst(location : 1: 4) = 'PATH';
			counter +=1;
			json_arrayPush ( pParameters  : swaggerPathParm (iterParms.this) ); 
		endif;
	enddo;

	json_moveObjectInto (pMethod : 'parameters' : pParameters);
	return pParameters;

end-proc;

// ------------------------------------------------------------------------------------
// countPathParms
// ------------------------------------------------------------------------------------
dcl-proc countPathParms;

	dcl-pi countPathParms int(5) ;
		pRoutine pointer value;
	end-pi;

	dcl-s counter int(5);	
	dcl-ds iterParms   	  likeds(json_iterator);  
	dcl-s location char(10);

	iterParms = json_setIterator(pRoutine:'parms');  
	dow json_ForEach(iterParms) ; 
		location = json_getStr(iterParms.this: 'annotations.location'); 
		if 	%subst(location : 1: 4) = 'PATH';
			counter +=1;
		endif;
	enddo;

	return counter;
end-proc;

// ------------------------------------------------------------------------------------
// build parm path names 
// ------------------------------------------------------------------------------------
dcl-proc pathParmsStr;

	dcl-pi pathParmsStr varchar(256);
		pRoutine pointer value;
		length   int(5) value;   
	end-pi;

	dcl-s counter int(5);	
	dcl-s str varchar(256);
	dcl-ds iterParms   	  likeds(json_iterator);  
	dcl-s location char(10);


	iterParms = json_setIterator(pRoutine:'parms');  
	dow json_ForEach(iterParms) and counter < length; 
		location = json_getStr(iterParms.this: 'annotations.location'); 
		if 	%subst(location : 1: 4) = 'PATH';
			counter +=1;
			str +=   '/{' 
				+   snakeToCamelCase(
						json_getStr(iterParms.this: 'parameter_name')
					) 
				+ '}';
		endif;
	enddo;

	return str;
end-proc;

/* was this before breaking up into parts: 
dcl-proc buildSwaggerJsonOrg;

	dcl-pi *n pointer;
		environment varchar(64) const options(*varsize);
		pRoutines pointer value;
	end-pi;

	dcl-ds iterList   	  likeds(json_iterator);  
	dcl-ds iterParms   	  likeds(json_iterator);  
	dcl-ds iterPathParms  likeds(json_iterator);
	dcl-s pPathParms  	  pointer;
	dcl-s pathParms       varchar(256);
	dcl-s pOpenApi  	  pointer;
	dcl-s pRoute 		  pointer;
	dcl-s pPaths  		  pointer;
	dcl-s pParms  		  pointer;
	dcl-s pParm   		  pointer;
	dcl-s pMethod 		  pointer;
	dcl-s pComponents 	  pointer;
	dcl-s pSchemas   	  pointer;
	dcl-s pPropertyInput  pointer;
	dcl-s pPropertyOutput pointer;
	dcl-s pParameters 	  pointer;
	dcl-s pParmsInput 	  pointer;
	dcl-s pParmsOutput 	  pointer;	
	dcl-s Schema   		  varchar(64);
	dcl-s Routine 		  varchar(64);
	dcl-s RoutineType 	  varchar(10);
	dcl-s RoutineTypeNc   varchar(10);
	dcl-s resultSets      int(5);
	dcl-s methods         varchar(256);
	dcl-s method          varchar(16);
	dcl-s endpoint        varchar(256);
	dcl-s pathName        varchar(256);
	dcl-s schemaOutput    varchar(256);
	dcl-s schemaInput     varchar(256);
	dcl-s pAnnotations    pointer;
	dcl-s description     varchar(1024);


	pOpenApi  =  openApiProlog();
	
	pPaths      = json_moveObjectInto  ( pOpenApi    : 'paths'      : json_newObject() ); 
	pComponents = json_moveObjectInto  ( pOpenApi    : 'components' : json_newObject()); 
	pSchemas    = json_moveObjectInto  ( pComponents : 'schemas'    : json_newObject()); 

	// Now produce the openAPI JSON fro each routine 
	iterList = json_setIterator(pRoutines);  
	dow json_ForEach(iterList) ;  


		
		schema =  json_getStr(iterList.this:'schema');
		routine = json_getStr(iterList.this:'routine'); 
		routinetype = json_getStr (iterList.this:'routine_type');
		description = json_getStr (iterList.this:'description');

		pAnnotations = json_locate (iterList.this:'annotations');
		routineTypeNc = NameCase (routinetype);
		endpoint = json_getstr ( pAnnotations : 'endpoint');
		if endpoint <= ''; 
			endpoint = routine + routineTypeNc;
		endif;

		method = strLower(json_getstr ( pAnnotations : 'method'));
		if method <= '';
			if routinetype = 'VIEW'; 
				method = 'get';
			elseif routinetype = 'SCALAR' // scalar
			or routinetype = 'TABLE'  // table
			or resultSets >= 1;       // Procedure with result set (open cursor)  
				method = 'get';
			else;
				method = 'post';
			endif;
		endif;


		schemaOutput = routine + nameCase(method) + 'Output' + routineTypeNc;
		schemaInput  = Routine + nameCase(method) + 'Input'  + routineTypeNc;
		
		resultSets  = json_getInt(iterList.this:'result_sets');
		if resultSets >= 1;
			schemaOutput = '"$ref":"#/components/schemas/DynamicResponse"';
		else;
			schemaOutput = '"$ref":"#/components/schemas/'  + schemaOutput + '"';	
		endif; 


		// make an endpoind for each path parm
		// TODO!! now only that the fist as a comple list 
		pathParms = getPathParms (iterList.this);
		pPathParms = json_newArray();
		json_arrayPush (pPathParms :'');
		if pathParms > '';
			json_arrayPush (pPathParms : pathParms);
		endif;


		iterPathParms = json_setIterator(pPathParms);  
		dow json_ForEach(iterPathParms) ;  

			pathParms = json_getStr(iterPathParms.this);
			
			if (method = 'patch' or method = 'put' or method = 'delete') and pathParms = '';
				// TODO !! for now both patch and put need a key on the path 
			else;   


				// When the endpoint exists - we just append each method
				pathName = '/' + environment + '/' + schema + '/' + endpoint + pathParms;
				pRoute = json_locate  ( pPaths : '"' + pathName +'"');
				if pRoute = *NULL; 
					pRoute = json_newObject();
					json_noderename (pRoute : pathName);
					json_nodeInsert ( pPaths  : pRoute : JSON_LAST_CHILD); 
				endif;


				pMethod = openApiMethod (
					schema:
					endpoint:
					description:
					method:
					schemaInput:
					schemaOutput
				);

				if json_getInt (iterList.this : 'implementations') > 1;
					json_setStr (pMethod  : 'summary' : 'This operation is polymorpich with  ' + 
						json_getStr (iterList.this : 'implementations') + 
						' implementations and can not be executed. Can not decide which to use'); 
				endif;

				if method = 'get' or method = 'delete' ;
					json_delete ( json_locate(pMethod : 'requestBody')); // get do not have a body

					json_moveObjectInto  ( pRoute  :  method  : pMethod ); 
					pParameters = json_moveObjectInto ( pMethod : 'parameters': json_newArray());

					iterParms = json_setIterator(iterList.this:'parms');  
					dow json_ForEach(iterParms) ;  
						if isInputInThisContext(iterParms.this : iterPathParms.this );
							json_arrayPush ( pParameters  : swaggerQueryParm (iterParms.this) ); 
						endif;
					enddo;


					pParmsOutput = json_moveObjectInto  ( pSchemas  :  schemaOutput  : json_newObject() ); 
					json_setStr(pParmsOutput : 'type' : 'object');
					pPropertyOutput  = json_moveObjectInto  ( pParmsOutput  :  'properties' : json_newObject() ); 

					if routinetype = 'SCALAR'; // scalar

						pParm = json_newObject(); 
						json_noderename (pParm : 'success' );
						json_setStr    (pParm : 'name'        : 'success');
						json_setStr    (pParm : 'type'        : 'boolean');
						json_nodeInsert ( pPropertyOutput  : pParm  : JSON_LAST_CHILD); 

						pParm = swaggerParm (
							json_getChild( 
								json_locate (iterList.this:'parms') 
							)
						);
						json_noderename (pParm : rootName());
						json_nodeInsert ( pPropertyOutput  : pParm  : JSON_LAST_CHILD); 


					else;
						iterParms = json_setIterator(iterList.this:'parms');  
						dow json_ForEach(iterParms) ;  
							if json_getStr (iterParms.this:'parameter_mode') = 'OUT'  ;
								json_nodeInsert ( pPropertyOutput  : swaggerParm (iterParms.this)  : JSON_LAST_CHILD); 
							endif;
						enddo;
					endif;
				else;	

					json_moveObjectInto  ( pRoute  :  method  : pMethod ); 

					pParmsInput = json_moveObjectInto  ( pSchemas  :  schemaInput   : json_newObject() ); 
					json_setStr(pParmsInput : 'type' : 'object');
					pPropertyInput  = json_moveObjectInto  ( pParmsInput  :  'properties' : json_newObject() ); 

					if resultSets = 0;
						pParmsOutput = json_moveObjectInto  ( pSchemas  :  schemaOutput  : json_newObject() ); 
						json_setStr(pParmsOutput : 'type' : 'object');
						pPropertyOutput  = json_moveObjectInto  ( pParmsOutput  :  'properties' : json_newObject() ); 
					endif;

					iterParms = json_setIterator(iterList.this:'parms');  
					dow json_ForEach(iterParms) ;  
						if isInputInThisContext(iterParms.this : iterPathParms.this );
							json_nodeInsert ( pPropertyInput  : swaggerParm (iterParms.this)  : JSON_LAST_CHILD); 
						endif;
						if resultSets = 0;
							if json_getStr (iterParms.this:'parameter_mode') = 'OUT' 
							or json_getStr (iterParms.this:'parameter_mode') = 'INOUT' ;
								json_nodeInsert ( pPropertyOutput  : swaggerParm (iterParms.this)  : JSON_LAST_CHILD); 
							endif;
						endif;
					enddo;
				endif; 
			endif;
		enddo;
		json_delete(pPathParms);
	enddo;	

	json_moveObjectInto  ( pOpenApi  :  'definitions' : definitions()  ); 
	json_moveObjectInto  ( pOpenApi  :  'externalDocs' : externalDocs() ); 

	return (pOpenApi);


end-proc;
*/

// ------------------------------------------------------------------------------------
// is Input In This Context
// ------------------------------------------------------------------------------------
dcl-proc isInputInThisContext;

	dcl-pi isInputInThisContext ind ;
		pParm      pointer value;
		pParmPath  pointer value;
	end-pi;

	dcl-s usage      varchar(10);

	usage = json_getStr (pParm:'usage') ;
	return usage = 'input';
	
end-proc;
// ------------------------------------------------------------------------------------
// get parameter from the path 
// ------------------------------------------------------------------------------------
dcl-proc getPathParms;

	dcl-pi getPathParms varchar(256);
		pRoutine pointer value;
	end-pi;

	dcl-ds iterParms  	likeds(json_iterator);  
	dcl-s pathParms  	varchar(256);
	dcl-s location  char(10);

	iterParms = json_setIterator(pRoutine:'parms');  
	dow json_ForEach(iterParms) ; 
		location = json_getStr(iterParms.this: 'annotations.location'); 
		if 	%subst(location : 1: 4) = 'PATH';
			pathParms += '/{' 
				+ snakeToCamelCase(
					json_getStr(iterParms.this: 'parameter_name')
				  ) 
			+ '}';
		endif;
	enddo;

	return pathParms;

end-proc;

// ------------------------------------------------------------------------------------
// Open api prolog
// ------------------------------------------------------------------------------------
dcl-proc openApiProlog ;

	dcl-pi *n pointer;
	end-pi;

	dcl-s url  varchar(256);
	dcl-s host varchar(256);
	dcl-s protocol varchar(256);
	dcl-s prefix  varchar(256);


	protocol = getHeader ('X-Forwarded-Proto');

	if protocol > '';
		host     = getHeader ('host');
		prefix   = getHeader ('X-Forwarded-Prefix');
		url = protocol + '://' + host + prefix;
	else;
		url = getServerVar('SERVER_URI');
	endif; 

	return  json_parseString(`{
		"openapi": "3.0.1",
		"info": {
			"title": "${ getServerVar('SERVER_DESCRIPTION') }",
			"version": "${ getServerVar('SERVER_SOFTWARE')}",
            "description": "Service endpoints made easy. powered by Sitemule"
		},
		"servers": [
			{
				"url": "${ url }",
				"description": "${ getServerVar('SERVER_SYSTEM_NAME') }"
			}
		]
	}`);



/* Base path ... 
	pOpenApi = json_parseString(`{
		"openapi": "3.0.1",
		"info": {
			"title": "${ getServerVar('SERVER_DESCRIPTION') }",
			"version": "${ getServerVar('SERVER_SOFTWARE')}"
		},
		"servers": [
			{
				"url": "${ getServerVar('SERVER_URI') }/noxdbapi/{environment}",
				"description": "${ getServerVar('SERVER_SYSTEM_NAME') }",
				"variables": {
					"port": {
						"enum": [
							"7007",
							"7008"
						],
						"default": "7007"
					},
					"environment":{
						"enum": [ ${ schemaList } ]
					} 

				}
			}
		]
	}`);
*/ 
end-proc;

// ------------------------------------------------------------------------------------
// openApiMethod
// ------------------------------------------------------------------------------------
dcl-proc openApiMethod;

	dcl-pi openApiMethod pointer;
		schema varchar(32) const;
		endpoint varchar(256) const;
		description varchar(1024) const;
		method varchar(32) const;
		schemaInput varchar(256) const;
		schemaOutput varchar(256) const;
	end-pi;

	dcl-s ref   		varchar(10) inz('$ref');
	dcl-s pMethod	pointer;


	pMethod = json_parseString(
		`{
			"tags": [
				"${schema}"
			],
			"operationId": "${endpoint}",
			"summary": "${description}",
			"requestBody": {
				"content": {
					"application/json": {
						"schema": {
							"${ref}": "#/components/schemas/${ schemaInput }"
						}
					}
				},
				"required": true
			},
			"responses": {
				"200": {
					"description": "Request completed normally",
					"content": {
						"application/json": {
							"schema": {
								"${ref}": "#/components/schemas/${ schemaOutput }"
							}
						}
					}
				},
				"403": {
					"description": "No response from service"
				},
				"404": {
					"description": "Resource not found",
					"content": {
						"application/json": {
							"schema": {
								"${ref}": "#/components/schemas/NotFoundResponse"
							}
						}
					}
				},
				"406": {
					"description": "Combination of parameters raises a conflict",
					"content": {
						"application/json": {
							"schema": {
								"${ref}": "#/components/schemas/ErrorResponse"
							}
						}
					}
				},
				"default": {
					"description": "Internal error",
					"content": {
						"application/json": {
							"schema": {
								"${ref}": "#/components/schemas/ErrorResponse"
							}
						}
					}

				}
			}
		}`);	

	return pMethod;

end-proc;
// ------------------------------------------------------------------------------------
// build the "root" of the response schema 
// ------------------------------------------------------------------------------------
dcl-proc buildResponseSchema;

	dcl-pi *n pointer;
		schemaName  varchar(256) value;
	end-pi;

	dcl-s pResponseSchema	pointer;
	dcl-s ref   varchar(10) inz('$ref');

	pResponseSchema = json_parseString( `
	{
		"type": "object",
		"properties": {
			"success": {
				"type": "boolean",
			},
			"root": {
				"type": "string"
			},
			"metaData": {
				"type": "object"
			},
			"${rootName()}": {
				"type" : "array",
				"items": {
					"${ref}": "#/components/schemas/${ schemaName }"
				}

			}
		}
	}`);

	return pResponseSchema;
	

end-proc; 
// ------------------------------------------------------------------------------------
// definitions
// ------------------------------------------------------------------------------------
dcl-proc definitions;

	dcl-pi definitions pointer;
	end-pi;

	return json_parseString( `
	{
		"DynamicResponse": {
			"type": "object",
			"properties": {
				"success": {
					"type": "boolean",
				},
				"root": {
					"type": "string"
				},
				"metaData": {
					"type": "object"
				},
				"${rootName()}": {
					"type" : "array",
					"items": {
                        "type": "object"
                    }

				}
			}
		},
		"OkResponse": {
			"type": "object",
			"properties": {
				"success": {
					"type": "boolean",
					"default": true
				}			
			}
		},
		"ErrorResponse": {
			"type": "object",
			"properties": {
				"success": {
					"type": "boolean",
					"default": false
				},
				"description": {
					"type": "string"
				},
				"message": {
					"type": "string"
				}
			}
		},
		"NotFoundResponse": {
			"type": "object",
			"properties": {
				"success": {
					"type": "boolean",
					"default": false
				},
				"${rootName()}": {
					"type": "string",
					"default": null
				}
			}
		}
	}`);

end-proc;
// ------------------------------------------------------------------------------------
// externalDocs
// ------------------------------------------------------------------------------------
dcl-proc externalDocs;

	dcl-pi externalDocs pointer;
	end-pi;

	dcl-s pExternal pointer;

	pExternal = json_newObject();
	json_setStr( pExternal : 'description' : 'Find out more about noxDbApi');
	json_setStr( pExternal : 'url': 'https://github.com/sitemule/noxDbApi');
	return pExternal;

end-proc;
// ------------------------------------------------------------------------------------
// swaggerCommonParmmeters
// ------------------------------------------------------------------------------------
dcl-proc swaggerCommonParmmeters;

	dcl-pi *N;
		pSwaggerParm pointer value;
		pMetaParm pointer value;
	end-pi;

	//dcl-s  location char(10);
//
	//location = json_getStr(pMetaParm: 'annotations.location');
//
	//json_setStr ( pSwaggerParm : 'description' : json_getStr   (pMetaParm : 'parmDescription'));
	//json_setStr ( pSwaggerParm : 'type'        : dataTypeJson  (pMetaParm ));
	////json_setStr ( pSwaggerParm : 'format'      : dataFormatJson(pMetaParm ));
	//json_setBool( pSwaggerParm : 'required'    : json_isnull   (pMetaParm : 'DEFAULT') );
	//if 	%subst(location: 1 :4) = 'PATH';
	//	json_setStr ( pSwaggerParm : 'in'      : 'path');
	//endif;
	//
	//if json_getInt (pMetaParm : 'CHARACTER_MAXIMUM_LENGTH') > 0;
	//	json_setInt     ( pSwaggerParm : 'maxLength'   : json_getInt (pMetaParm : 'CHARACTER_MAXIMUM_LENGTH'));
	//endif;

	json_setStr    ( pSwaggerParm : 'type'        : dataTypeJson  (pMetaParm ));
	json_setInt    ( pSwaggerParm : 'maxLength'   : json_getInt (pMetaParm : 'length'));

end-proc;

// ------------------------------------------------------------------------------------
// swaggerQueryParm
// ------------------------------------------------------------------------------------
dcl-proc swaggerQueryParm;

	dcl-pi swaggerQueryParm pointer ;
		pMetaParm pointer value;
	end-pi;

	dcl-s pParm pointer; 
	dcl-s parmType int(5); 
	dcl-s name varchar(64);

	name = snakeToCamelCase(json_getstr (pMetaParm : 'parameter_name') );
	if name = '';
		name = 'parm' + json_getstr (pMetaParm : 'ordinal_position'); 
	endif;

	pParm = json_newObject(); 

	json_setStr ( pParm : 'name' : name);
	json_setStr ( pParm : 'in' : 'query');
	swaggerCommonParmmeters ( pParm : pMetaParm);

	return pParm;


end-proc;
// ------------------------------------------------------------------------------------
// swaggerPathParm
// ------------------------------------------------------------------------------------
dcl-proc swaggerPathParm;

	dcl-pi swaggerPathParm pointer ;
		pMetaParm pointer value;
	end-pi;

	dcl-s pParm pointer; 
	dcl-s parmType int(5); 
	dcl-s name varchar(64);

	name = snakeToCamelCase(json_getstr (pMetaParm : 'parameter_name') );
	if name = '';
		name = 'parm' + json_getstr (pMetaParm : 'ordinal_position'); 
	endif;

	pParm = json_newObject(); 

	json_setStr ( pParm : 'name' : name);
	json_setStr ( pParm : 'in' : 'path');
	swaggerCommonParmmeters ( pParm : pMetaParm);

	return pParm;


end-proc;
// ------------------------------------------------------------------------------------
// swaggerParm
// ------------------------------------------------------------------------------------
dcl-proc swaggerParm;

	dcl-pi swaggerParm pointer ;
		pMetaParm pointer value;
	end-pi;

	dcl-s pParm pointer; 
	dcl-s parmType int(5); 
	dcl-s name varchar(64);
	
	name = snakeToCamelCase(json_getstr (pMetaParm : 'name') );

	pParm = json_newObject(); 
	json_noderename( pParm : name );
	swaggerCommonParmmeters ( pParm : pMetaParm);

	return pParm;

end-proc;

// ------------------------------------------------------------------------------------
// snakeToCamelCase
// ------------------------------------------------------------------------------------
dcl-proc snakeToCamelCase;

	dcl-pi snakeToCamelCase varchar(256) ;
		text varchar(256) const options(*varsize);
	end-pi;

	dcl-s temp varchar(256);
	dcl-s i int(5);

	temp = strLower (text); 

	for i = 1 to %len(temp); 
		if %subst(temp: i : 1) = '_';
			 %subst(temp: i ) = %subst(temp: i +1);
			 %subst(temp: i : 1) = strUpper(%subst(temp: i : 1));
		endif;
	endfor; 

	return %trimr(temp);

end-proc;
// ------------------------------------------------------------------------------------
// camelToSnakeCase
// ------------------------------------------------------------------------------------
dcl-proc camelToSnakeCase;

	dcl-pi *n varchar(256) ;
		text varchar(256) const options(*varsize);
	end-pi;

	dcl-s low  varchar(256);
	dcl-s temp varchar(256);
	dcl-s i int(5);

	temp = '';
	low  = strLower  (text); 

	for i = 1 to %len(text);
		if %subst(text: i : 1) <> %subst(low: i : 1) ;
			temp +=  '_' + %subst(low: i : 1);
		else; 
			temp += %subst(text : i : 1);
		endif;
	endfor; 

	return temp;

end-proc;
// ------------------------------------------------------------------------------------
// dataTypeJson
// ------------------------------------------------------------------------------------
dcl-proc dataTypeJson;

	dcl-pi *n varchar(64);
		pMetaParm pointer value;
	end-pi;

	dcl-s inputType varchar(64);
	//dcl-s userType varchar(256);
	dcl-s numericScale int (5);
	dcl-s numericPrecision int (5);

    //userType = json_getstr (pMetaParm : 'data_type_name');
	inputType = json_getstr (pMetaParm : 'type');
	numericScale = json_getint (pMetaParm : 'numeric_scale'); // Decimals after 
	numericPrecision = json_getint (pMetaParm : 'numeric_precision');

	select; 
		//when %scan('BOOL' :  userType) > 0;
		//	return 'boolean';

		when inputType = 'int' 
		or   (inputType = 'packed' and numericScale =0)
		or   (inputType = 'zoned'  and numericScale =0);
			return 'integer';

		when inputType = 'packed' 
		or   inputType = 'zoned'; 
		// or   inputType = 'DECFLOAT' // more to come:
		// or   inputType = 'REAL' // more to come:
		// or   inputType = 'FLOAT' // more to come:
		// or   inputType = 'DOUBLE'; // more to come:
			return 'number';

		other;
			return 'string';
	endsl;

end-proc;

// ------------------------------------------------------------------------------------
// dataFormatJson
// ------------------------------------------------------------------------------------
dcl-proc dataFormatJson;

	dcl-pi *n varchar(64);
		pMetaParm pointer value;
	end-pi;

	dcl-s inputType varchar(64);
	dcl-s formatString varchar(64);
	dcl-s numericScale int (5);
	dcl-s numericPrecision int (5);
	 
	inputType = json_getstr (pMetaParm : 'type');
	numericScale = json_getint (pMetaParm : 'numeric_scale'); // Decimals after 
	numericPrecision = json_getint (pMetaParm : 'length');

	select; 
		when   inputType = 'int' 
		or    (inputType = 'packed' and numericScale =0 and numericPrecision > 9)
		or    (inputType = 'zoned' and numericScale =0 and numericPrecision > 9);
			return 'int64';
 
		when inputType = 'int' 
		or    (inputType = 'packed' and numericScale =0 and numericPrecision <= 9)
		or    (inputType = 'zoned' and numericScale =0 and numericPrecision <= 9);
			return 'int32';

		when inputType = 'packed' 
		or   inputType = 'zoned'; 
		// more to come:: or   inputType = 'DECFLOAT' 
		// more to come:: or   inputType = 'REAL' 
		// more to come:: or   inputType = 'FLOAT' 
		// more to come:: or   inputType = 'DOUBLE'; 
			return 'double';

		when inputType = 'DATE'; 
			return 'date';

		when inputType = 'TIMESTAMP'; 
			return 'datetime';

		other;
			return dataTypeAsText (pMetaParm);
	endsl;

end-proc;

// ------------------------------------------------------------------------------------
// Data type in text
// ------------------------------------------------------------------------------------
dcl-proc dataTypeAsText;

	dcl-pi *n varchar(64);
		pMetaParm pointer value;
	end-pi;

	dcl-s inputType varchar(64);
	dcl-s formatString varchar(64);
	dcl-s numericScale int (5);
	dcl-s length int (20);

	 
	inputType = json_getstr (pMetaParm : 'type');
	numericScale = json_getint (pMetaParm : 'numeric_scale'); // Decimals after 

	if json_isnull (pMetaParm : 'length');
		length = json_getint (pMetaParm : 'character_maximum_length');
	else;
		length = json_getint (pMetaParm : 'length');
	endif;


	formatString =  strLower(inputType + '(' + %char(length));
	if numericScale > 0; 
		formatString += ',' + %char(numericScale);
	endif;
	formatString += ')';
	return formatString;

end-proc;

// ------------------------------------------------------------------------------------
// Parse Annotations, and remove annotations from the string 
// The annotation @Method in the description makes the procedure visible in the openAPI( swagger) user interface: 
// The annotation @Endpoint is the name of the endpoint
// comment on procedure corpdata.employee_set is 'Update Employee information @Method=PATCH @Endpoint=employee';
// ------------------------------------------------------------------------------------
dcl-proc parseAnnotations;

	dcl-pi parseAnnotations  pointer;
		description  varchar(2000) ;
	end-pi;

	dcl-s pAnnotations pointer;
	dcl-s at	int(5);
	dcl-s eq	int(5);
	dcl-s end   int(5);
	dcl-s st 	int(5) inz(1);
	dcl-s value	varchar(256);
	dcl-s annotation	varchar(256);

	pAnnotations = json_newObject();

	dou at = 0 or eq = 0;
		at = %scan ('@' : description : st);
		if  at > 0; 
			eq = %scan ('=' : description : at);
			if eq > 0;
				annotation = %subst(description : at +1 : eq - at -1 );
				end = %scan (' ' : description : eq);
				if  end > 0;
					value  = %subst(description : eq +1 : end - eq -1 );
					st = end;
				else;
					value  = %subst(description : eq +1);
					st = %len(description);
				endif; 
				json_setStr ( pAnnotations : annotation : value);
				%subst ( description : at : st - at + 1 ) = '';
			endif;
		endif;
	enddo;

	description = %trimr (description);

	return pAnnotations;

end-proc;
// ------------------------------------------------------------------------------------
// root Name for resultsets
// ------------------------------------------------------------------------------------
dcl-proc rootName;

	dcl-pi rootName varchar(32);
	end-pi;

	dcl-s rootName 	varchar(32) static;

	if rootName = '';
		rootName = getenvvar('NOXDBAPI_ROOT_NAME'); 
		if  rootName = '';
			rootName = 'data';
		endif;
		// Dont use this - it will crumble all other interactions with noxdb
		// json_sqlSetRootName (rootName);  
	endif;

	return rootName;
end-proc;
// ------------------------------------------------------------------------------------
// rename the root Name for resultsets
// ------------------------------------------------------------------------------------
dcl-proc renameResultRoot;

	dcl-pi *n pointer;
		pResult pointer value;
		rootName varchar(32) const;
	end-pi;

	dcl-s pJson	pointer;

	pJson = json_locate(pResult : 'rows');
	if pJson <> *NULL;
		json_noderename (pJson : rootName);
		json_setstr (pResult : 'root' : rootName);
	endif;

	return pResult;
end-proc;

// ------------------------------------------------------------------------------------
// Upercase first letter 
// ------------------------------------------------------------------------------------
dcl-proc capitalize;

	dcl-pi *n varchar(256) ;
		str varchar(256) const options(*varsize);
	end-pi;

	if %len(str) >= 2;
		return strUpper ( %subst(str : 1 : 1) ) + %subst(str : 2 );
	elseif %len(str) = 1;
		return strUpper ( %subst(str : 1 : 1) ) ;
	else; 
		return '';
	endif;

end-proc;

