﻿<%@ free="*YES" language="SQLRPGLE" runasowner="*YES" owner="QPGMR"%>
<%
ctl-opt copyright('System & Method (C), 2019-2023');
ctl-opt decEdit('0,') datEdit(*YMD.) main(main); 
ctl-opt bndDir('NOXDB':'ICEUTILITY':'QC2LE');

/* -----------------------------------------------------------------------------
	Service . . . : Stored procedure router 
	Author  . . . : Niels Liisberg 
	Company . . . : System & Method A/S
	

	noxdbapi is a simple way to expose stored procedures as RESTservice. 
	Note - you might contain the services you expose either by access fsecurity
	or by user defined access rules added to this code - Whatever serves you best.

	

	1) Copy this code to your own server root and 
	compile this stored procedure router - Supply your file and serverid:

	CRTICEPGM STMF('/prj/noxDbApi/noxDbApi.rpgle') SVRID(noxDbApi)


	2) Any procedures can be used - also supporting if that returns one dynamic result set:
	
	Example:
	
	Build a test stored procedure - paste this into ACS:

	-- Procedure returns a resultset
	--------------------------------
	CREATE or REPLACE PROCEDURE  noxDbApi.services_info_list  (
		in service_search_name  varchar(20) default null
	)
	LANGUAGE SQL 
	DYNAMIC RESULT SETS 1

	BEGIN

		declare c1 cursor with return for
		select * 
		from   qsys2.services_info
		where  service_search_name is null 
		or     upper(service_name) like '%' concat upper(service_search_name) concat '%';

		open c1;

	END; 

	comment on procedure noxDbApi.services_info_list is 'Services info List';
	comment on parameter noxDbApi.services_info_list (service_search_name is 'Search services by name');

	3) Test if the procedure works in ACS:

	call noxDbApi.services_info_list (service_search_name => 'ptf');
	call noxDbApi.services_info_list ();


	
	4) Enable noxdbapi in your web config:
	
	Add the noxdbapi in the routing section in you webconfig.xml file in your server root:

	<routing strict="false">
		<map pattern="^/noxdbapi/" pgm="noxdbapi" lib="*LIBL" />
	</routing>



	5) Load the openAPI / (swagger) interface for the noxDbApi schema
	
	http://MY_IBM_I:7007/noxdbapi/




	By     Date       PTF     Description
	------ ---------- ------- ---------------------------------------------------
	NLI    23.05.2023         New program
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
 	
	rootName(); // TODO for now just initialize; 

	url = getServerVar('REQUEST_FULL_PATH');
	environment = strLower(word (url:1:'/'));
	schemaName  = word (url:2:'/');
	procName    = word (url:3:'/');		

	if  schemaName = 'openapi-meta';
		// The envvar is set in the "webconfig.xml" file. The "envvar" tag
		serveListSchemaProcs (
			environment : 
			getenvvar('NOXDBAPI_EXPOSE_SCHEMAS') : 
			getenvvar('NOXDBAPI_EXPOSE_ROUTINES')
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
			getenvvar('NOXDBAPI_EXPOSE_ROUTINES')
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
	end-pi;
	dcl-s pResponse		pointer;		
	dcl-s msg 			varchar(512);	
	dcl-s pPayload      pointer;	
	dcl-s name  		varchar(64);
	dcl-s value  		varchar(32760);
	dcl-s pathParm      varchar(256);
	dcl-s parmList  	varchar(32760);
	dcl-s sqlStmt   	varchar(32760);
	dcl-s specificName  varchar(128);
	dcl-s pRoutineMeta  pointer;
	dcl-s len 			int(10);
	dcl-s parmNum    	int(10);
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

	// path parameters given? find the name and add to the payload:
	if exposeRoutines = 'ANNOTATED';
		for parmNum = 1 to 10;
			pathParm = word ( url: parmNum + 3: '/'); // TODO !! now  path parms start after the endpoint ( word 4 ..) , that will change!!
			if pathParm = '';
				leave;
			endif;
			json_setValue (pPayload : getParmName ( schema : procName : parmNum) : pathParm );
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
	iterList = json_setIterator(pResponse);  
	dow json_ForEach(iterList) ;  
		json_noderename (iterList.this : snakeToCamelCase ( json_getname (iterList.this) ));
	enddo; 


	return;

on-exit; 

	if   json_locate (pResponse : rootName) <> *NULL
	and  json_isnull (pResponse : rootName);
		setStatus ('404');
	elseif json_getstr(pResponse : 'success') = 'false';
		msg = json_getstr(pResponse: 'message');
		if msg = '';
			msg = json_getstr(pResponse: 'msg');
		endif;
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
		where  routine_schema = :schema 
		and routine_type      = :routineType 
		and    routine_name   = :routine
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
	schema  = strUpper(camelToSnakeCase (schema));

	// Note: to make the endpoint unique:
	// 1) a blank has to follow the method name 
	// 2) The endpoint name has to terminate the textstring 
	exec sql 
		select specific_name  
		into   :specificName
		from   qsys2.sysroutines
		where  routine_schema = :schema 
		and    long_comment like '%@Method=' || :method || '%'
		and    ( long_comment like '%@Endpoint=' || :routine  || ' %'
		  or     long_comment like '%@Endpoint=' || :routine  );

	return schema + '.' + specificName;
end-proc;
// ------------------------------------------------------------------------------------
// get parameter name from a specific routing name by annotations 
// ------------------------------------------------------------------------------------
dcl-proc getParmName;

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

	method = getServerVar('REQUEST_METHOD');
	schema  = strUpper(camelToSnakeCase (schema));

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
		and    r.long_comment like '%@Method=' || :method || '%'
		and    ( r.long_comment like '%@Endpoint=' || :routine  || ' %'
		  or     r.long_comment like '%@Endpoint=' || :routine  )
        and    p.long_comment like '%@Parameter=PATH%'
        order by ordinal_position
        limit 1 offset :parmNumber - 1; // Offset starts at 0 and we ask for parameter number starting at 1 


	return snakeToCamelCase (parameterName);
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

	return json_parseString ('{"success": true}');

end-proc;

/* -------------------------------------------------------------------- *\ 
   produce JSON catalog
\* -------------------------------------------------------------------- */
dcl-proc serveListSchemaProcs;

	dcl-pi *n;
		environment 	varchar(64)  const options(*varsize);
		schemaNameList 	varchar(256) const options(*varsize);
		exposeRoutines  varchar(256) const options(*varsize);
	end-pi;

	dcl-s pResult      	pointer; 
	dcl-s pSwagger     	pointer; 
	dcl-s pRoutineTree 	pointer;
	
	dcl-ds iterList  	likeds(json_iterator);
	dcl-s  prevSchema   varchar(64);
	dcl-s  prevRoutine 	varchar(64);
	dcl-s  schemaList   varchar(256);
	dcl-s  filterAnnotated varchar(64);

	// Convert the list to SQL format of "IN" 
	schemaList = '''' + %scanrpl (',':''',''': schemaNameList) + '''';
	
	if exposeRoutines = 'ANNOTATED';
		filterAnnotated = ' and r.long_comment like ''%@Method%'' ';
	endif;

	pResult = json_sqlResultSet (`
		with 
			routines as ( 
				select 
					case function_type
						when 'S' then 'SCALAR'
						when 'T' then 'TABLE'
						else          'PROCEDURE'
					end routine_type,
					routine_schema , 
					routine_name, 
					specific_schema,
					specific_name, 
					long_comment,
					max_dynamic_result_sets
					from sysroutines 
				where routine_schema in (${schemaList}) 
			), 
			implementation as ( 
				select count(*) number_of_implementations, routine_type, routine_schema,routine_name
				from routines
				group by routine_type, routine_schema,routine_name
			)
		select 
			i.number_of_implementations,
			r.routine_type, 
			r.routine_name,
			r.long_comment desc,
			r.max_dynamic_result_sets,
			p.*
		from routines r
		join implementation i 
			on (r.routine_type, r.routine_schema,r.routine_name) = (i.routine_type, i.routine_schema,i.routine_name)
		left join sysparms p 
			on (r.specific_schema , r.specific_name ) = (p.specific_schema ,p.specific_name)
	    where i.number_of_implementations = 1
		${filterAnnotated}
		order by r.routine_schema , r.routine_name, ordinal_position;
	`);

	pRoutineTree = reorderResultAsTree (pResult);
	pSwagger = buildSwaggerJson (environment : pRoutineTree);

	SetContentType ('application/json');
	responseWriteJson(pSwagger);

	json_delete (pRoutineTree);
	json_delete (pResult);
	json_delete (pSwagger);


end-proc;
// --------------------------------------------------------------------  
dcl-proc reorderResultAsTree; 

	dcl-pi *n pointer;
		pRoutines  pointer value;
	end-pi;

	dcl-ds iterList  		 likeds(json_iterator);  
	dcl-s  pTree     		 pointer;
	dcl-s  pRoutine  		 pointer;
	dcl-s  pParms    		 pointer;
	dcl-s  Schema    		 varchar(64);
	dcl-s  Routine 	 		 varchar(128);
	dcl-s  RoutineType 		 varchar(10);
	dcl-s  PrevRoutineType 	 varchar(10);
	dcl-s  prevSchemaRoutine varchar(256);
	dcl-s  schemaRoutine 	 varchar(256);
	dcl-s  description  	 varchar(2000);

	pTree  = json_newArray ();

	// One item for each routine;
	iterList = json_setIterator(pRoutines);  
	dow json_ForEach(iterList) ;  

		schema =  snakeToCamelCase (json_getStr (iterList.this:'specific_schema'));
		routine = snakeToCamelCase (json_getStr (iterList.this:'routine_name')); 
		SchemaRoutine =  schema + '/' + routine;
		routineType = json_getStr(iterList.this: 'routine_type' );
		description = json_getStr(iterList.this: 'desc');

		if  schemaRoutine <> prevSchemaRoutine
		or  routineType   <> prevRoutineType;
			prevSchemaRoutine = SchemaRoutine;
			prevRoutineType =  routineType;
			pRoutine = json_newObject();
			json_moveObjectInto  ( pRoutine  :  'annotations' : parseAnnotations ( description) );
			json_setStr  (pRoutine : 'schema' :schema );
			json_setStr  (pRoutine : 'routine':routine );
			json_setStr  (pRoutine : 'routine_type': routineType);
			json_setStr  (pRoutine : 'description' : description ) ;
			json_setInt  (pRoutine : 'result_sets' : json_getInt(iterList.this: 'max_dynamic_result_sets'));
			json_setInt  (pRoutine : 'implementations' : json_getInt(iterList.this: 'number_of_implementations'));
			
			pParms = json_moveObjectInto  ( pRoutine  :  'parms' : json_newArray() ); 
			json_arrayPush(pTree : pRoutine);
		endif;
		// Parameter beef-up
		if json_isnull (iterList.this : 'long_comment' ); 
			description = json_getStr ( iterList.this : 'parameter_name') ;
		else;
			description = json_getStr ( iterList.this : 'long_comment');
			json_moveObjectInto  ( iterList.this :  'annotations' : parseAnnotations ( description) );
		endif; 
		description += ' as ' + dataTypeAsText(iterList.this);
		json_setStr (iterList.this:'parmDescription':description );
		json_arrayPush(pParms : iterList.this: JSON_COPY_CLONE);
	enddo;

	// debug
	json_WriteJsonStmf(pTree:'/prj/noxdbapi/debug/routine-tree.json':1208:*OFF);

	return pTree;


end-proc;
// --------------------------------------------------------------------  
dcl-proc buildSwaggerJson;

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
	dcl-s OutputReference varchar(256);
	dcl-s methods         varchar(256);
	dcl-s method          varchar(16);
	dcl-s endpoint        varchar(256);
	dcl-s pathName        varchar(256);
	dcl-s outRefSchema    varchar(256);
	dcl-s inRefSchema     varchar(256);
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
			if routinetype = 'SCALAR' // scalar
			or routinetype = 'TABLE'  // table
			or resultSets >= 1;       // Procedure with result set (open cursor)  
				method = 'get';
			else;
				method = 'post';
			endif;
		endif;


		outRefSchema = routine + nameCase(method) + 'Output' + routineTypeNc;
		inRefschema  = Routine + nameCase(method) + 'Input'  + routineTypeNc;
		
		resultSets  = json_getInt(iterList.this:'result_sets');
		if resultSets >= 1;
			OutputReference = '"$ref":"#/definitions/ApiResponse"';
		else;
			OutputReference = '"$ref":"#/components/schemas/'  + outRefSchema + '"';	
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
					routine:
					method:
					inRefschema:
					OutputReference
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


					pParmsOutput = json_moveObjectInto  ( pSchemas  :  outRefSchema  : json_newObject() ); 
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

					pParmsInput = json_moveObjectInto  ( pSchemas  :  inRefSchema   : json_newObject() ); 
					json_setStr(pParmsInput : 'type' : 'object');
					pPropertyInput  = json_moveObjectInto  ( pParmsInput  :  'properties' : json_newObject() ); 

					if resultSets = 0;
						pParmsOutput = json_moveObjectInto  ( pSchemas  :  outRefSchema  : json_newObject() ); 
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
// ------------------------------------------------------------------------------------
// is Input In This Context
// ------------------------------------------------------------------------------------
dcl-proc isInputInThisContext;

	dcl-pi isInputInThisContext ind ;
		pParm      pointer value;
		pParmPath  pointer value;
	end-pi;

	dcl-s pathParms varchar(256);
	dcl-s mode      varchar(10);

	pathParms = json_getStr(pParmPath);
	mode = json_getStr (pParm:'parameter_mode') ;

	if mode = 'IN'  ;
		if 	(json_getStr(pParm: 'annotations.Parameter') = 'PATH' and pathParms > '')
		or  (json_getStr(pParm: 'annotations.Parameter') = ''     and pathParms = '');
			return *ON;
		endif;
	elseif mode = 'INOUT' ;
		return *ON;
	endif; 

	return *off;
	
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

	iterParms = json_setIterator(pRoutine:'parms');  
	dow json_ForEach(iterParms) ; 
		if 	json_getStr(iterParms.this: 'annotations.Parameter') = 'PATH';
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
			"version": "${ getServerVar('SERVER_SOFTWARE')}"
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
		routine varchar(128) const;
		method varchar(32) const;
		inRefSchema varchar(256) const;
		OutputReference varchar(256) const;
	end-pi;

	dcl-s ref   		varchar(10) inz('$ref');

	return 	json_parseString(
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
							"${ref}": "#/components/schemas/${inRefSchema}"
						}
					}
				},
				"required": true
			},
			"responses": {
				"200": {
					"description": "OK",
					"content": {
						"application/json": {
							"schema": {
								${OutputReference}
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
								"${ref}": "#/definitions/notFound"
							}
						}
					}

				}
				"406": {
					"description": "Combination of parameters raises a conflict"
				},
				"default": {
					"description": "Internal error",
					"content": {
						"application/json": {
							"schema": {
								"${ref}": "#/definitions/error"
							}
						}
					}

				}
			}
		}`);	


end-proc;

// ------------------------------------------------------------------------------------
// definitions
// ------------------------------------------------------------------------------------
dcl-proc definitions;

	dcl-pi definitions pointer;
	end-pi;

	return json_parseString( `
	{
		"ApiResponse": {
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
		"error": {
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
		"notFound": {
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

	json_setStr ( pSwaggerParm : 'description' : json_getStr   (pMetaParm : 'parmDescription'));
	json_setStr ( pSwaggerParm : 'type'        : dataTypeJson  (pMetaParm ));
	json_setStr ( pSwaggerParm : 'format'      : dataFormatJson(pMetaParm ));
	json_setBool( pSwaggerParm : 'required'    : json_isnull   (pMetaParm : 'DEFAULT') );
	if 	json_getStr(pMetaParm: 'annotations.Parameter') = 'PATH';
		json_setStr ( pSwaggerParm : 'in'      : 'path');
	endif;
	
	if json_getInt (pMetaParm : 'CHARACTER_MAXIMUM_LENGTH') > 0;
		json_setInt     ( pSwaggerParm : 'maxLength'   : json_getInt (pMetaParm : 'CHARACTER_MAXIMUM_LENGTH'));
	endif;

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
// swaggerParm
// ------------------------------------------------------------------------------------
dcl-proc swaggerParm;

	dcl-pi swaggerParm pointer ;
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
	dcl-s userType varchar(256);
	dcl-s numericScale int (5);
	dcl-s numericPrecision int (5);

    userType = json_getstr (pMetaParm : 'data_type_name');
	inputType = json_getstr (pMetaParm : 'data_type');
	numericScale = json_getint (pMetaParm : 'numeric_scale'); // Decimals after 
	numericPrecision = json_getint (pMetaParm : 'numeric_precision');

	select; 
		when %scan('BOOL' :  userType) > 0;
			return 'boolean';

		when inputType = 'INTEGER' 
		or   inputType = 'SMALLINT' 
		or   inputType = 'BIGINT' 
		or   (inputType = 'DECIMAL' and numericScale =0)
		or   (inputType = 'NUMERIC' and numericScale =0);
			return 'integer';

		when inputType = 'DECIMAL' 
		or   inputType = 'NUMERIC' 
		or   inputType = 'DECFLOAT' 
		or   inputType = 'REAL' 
		or   inputType = 'FLOAT' 
		or   inputType = 'DOUBLE'; 
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
	 
	inputType = json_getstr (pMetaParm : 'data_type');
	numericScale = json_getint (pMetaParm : 'numeric_scale'); // Decimals after 
	numericPrecision = json_getint (pMetaParm : 'numeric_precision');

	select; 
		when   inputType = 'BIGINT' 
		or    (inputType = 'DECIMAL' and numericScale =0 and numericPrecision > 9)
		or    (inputType = 'NUMERIC' and numericScale =0 and numericPrecision > 9);
			return 'int64';
 
		when inputType = 'INTEGER' 
		or   inputType = 'SMALLINT' 
		or    (inputType = 'DECIMAL' and numericScale =0 and numericPrecision <= 9)
		or    (inputType = 'NUMERIC' and numericScale =0 and numericPrecision <= 9);
			return 'int32';

		when inputType = 'DECIMAL' 
		or   inputType = 'NUMERIC' 
		or   inputType = 'DECFLOAT' 
		or   inputType = 'REAL' 
		or   inputType = 'FLOAT' 
		or   inputType = 'DOUBLE'; 
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

	 
	inputType = json_getstr (pMetaParm : 'data_type');
	numericScale = json_getint (pMetaParm : 'numeric_scale'); // Decimals after 

	if json_isnull (pMetaParm : 'numeric_precision');
		length = json_getint (pMetaParm : 'character_maximum_length');
	else;
		length = json_getint (pMetaParm : 'numeric_precision');
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
		json_sqlSetRootName (rootName);  
	endif;
	

	return rootName;
end-proc;
