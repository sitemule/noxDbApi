﻿<%@ free="*YES" language="RPGLE" runasowner="*YES" owner="QPGMR"%>
<%
ctl-opt copyright('System & Method (C), 2019-2023');
ctl-opt decEdit('0,') datEdit(*YMD.) main(main); 
ctl-opt bndDir('NOXDB':'ICEUTILITY':'QC2LE');

/* -----------------------------------------------------------------------------
	Service . . . : Stored procedure router 
	Author  . . . : Niels Liisberg 
	Company . . . : System & Method A/S
	

	noxdbapi is a simple way to expose stored procedures as RESTservice. 
	Note - you might contain the services you expose either by access security
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
	dcl-s environment   varchar(32);
	dcl-s schemaName    varchar(32);
	dcl-s procName 		varchar(128);
 	

	url = getServerVar('REQUEST_FULL_PATH');
	environment = strLower(word (url:1:'/'));
	schemaName  = word (url:2:'/');
	procName    = word (url:3:'/');

	if  schemaName = 'openapi-meta';
		// The envvar is set in the "webconfig.xml" file. The "envvar" tag
		serveListSchemaProcs (environment : getenvvar('NOXDBAPI_EXPOSE_SCHEMAS')); 
	elseif schemaName = 'static_resources' or procName = ''; 
		serveStatic (environment : schemaName : url);
	else;
		serveProcedureResponse (environment : schemaName : procName);
	endif; 


end-proc;
// --------------------------------------------------------------------  
dcl-proc serveStatic;

	dcl-pi *n;
		environment varchar(32);
		schemaName varchar(32);
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
		environment  varchar(32);
		schema       varchar(32);
		procName     varchar(128);
	end-pi;
	
	dcl-s pResponse		pointer;		
	dcl-s msg 			varchar(512);	
	dcl-s pPayload      pointer;	
	dcl-s name  		varchar(64);
	dcl-s value  		varchar(32760);
	dcl-s parmList  	varchar(32760);
	dcl-s sqlStmt   	varchar(32760);
	dcl-s pRoutineMeta  pointer;
	dcl-s len 			int(10);
	dcl-ds iterParms  	likeds(json_iterator);
	dcl-ds iterList  	likeds(json_iterator);  
	

	SetContentType ('application/json;charset=UTF-8');


	if schema <= '';
		pResponse =FormatError (
			'Need schema and procedure'
		);
		return;
	endif;

	pPayload = json_ParseRequest();

	// When payload is not posted ( aka not a object) we create it from the url parameters
	if json_getChild (pPayload) = *NULL; 
		json_delete(pPayload);
		pPayload = json_newObject();
		getQryStrList ( name : value : '*FIRST');
		dow name > '';
			json_setValue (pPayload : camelToSnakeCase(name) : value );
			getQryStrList ( name : value : '*NEXT');
		enddo;
	else; 
		iterList = json_setIterator(pPayload);  
		dow json_ForEach(iterList) ;  
			json_noderename (iterList.this : camelToSnakeCase ( json_getname (iterList.this) ));
		enddo; 

	endif;

	pResponse = json_sqlExecuteRoutine (
		schema + '.' + camelToSnakeCase(procName) : 
		pPayload : 
		JSON_META + JSON_CAMEL_CASE + JSON_GRACEFUL_ERROR
	);

	//	if json_Error(pResponse);
	//		consolelog(sqlStmt);
	//		pResponse= FormatError (
	//			'Invalid action or parameter: '  
	//		);
	//	endif;

	// The result will be in snake ( as is). JSON is typically Cammel 
	// json_sqlExecuteRoutine is not supporting the JSON_CAMEL_CASE ( yet)  	
	iterList = json_setIterator(pResponse);  
	dow json_ForEach(iterList) ;  
		json_noderename (iterList.this : snakeToCamelCase ( json_getname (iterList.this) ));
	enddo; 


	return;

on-exit; 

	if   json_locate (pResponse : 'result') <> *NULL
	and  json_isnull (pResponse : 'result');
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
		environment 	varchar(32) const options(*varsize);
		schemaNameList 	varchar(256) const options(*varsize);
	end-pi;

	dcl-s pResult      	pointer; 
	dcl-s pSwagger     	pointer; 
	dcl-s pRoutineTree 	pointer;
	
	dcl-ds iterList  	likeds(json_iterator);
	dcl-s  prevSchema   varchar(32);
	dcl-s  prevRoutine 	varchar(32);
	dcl-s  schemaList   varchar(256);

	// Convert the list to SQL format of "IN" 
	schemaList = '''' + %scanrpl (',':''',''': schemaNameList) + '''';

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
		order by r.routine_schema , r.routine_name;
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

	dcl-ds iterList  likeds(json_iterator);  
	dcl-s  pTree     pointer;
	dcl-s  pRoutine  pointer;
	dcl-s  pParms    pointer;
	dcl-s  Schema    varchar(32);
	dcl-s  Routine 	 varchar(128);
	dcl-s prevSchemaRoutine varchar(256);
	dcl-s schemaRoutine varchar(256);

	pTree  = json_newArray ();

	// One item for each routine;
	iterList = json_setIterator(pRoutines);  
	dow json_ForEach(iterList) ;  

		schema =  snakeToCamelCase (json_getStr (iterList.this:'specific_schema'));
		routine = snakeToCamelCase (json_getStr (iterList.this:'routine_name')); 
		SchemaRoutine =  schema + '/' + routine;

		if  schemaRoutine <> prevSchemaRoutine;
			prevSchemaRoutine = SchemaRoutine;
			pRoutine = json_newObject();
			json_setStr  (pRoutine : 'schema' :schema );
			json_setStr  (pRoutine : 'routine':routine );
			json_setStr  (pRoutine : 'routine_type': json_getStr(iterList.this: 'routine_type' ));
			json_setStr  (pRoutine : 'description' : json_getStr(iterList.this: 'desc')) ;
			json_setInt  (pRoutine : 'result_sets' : json_getInt(iterList.this: 'max_dynamic_result_sets'));
			json_setInt  (pRoutine : 'implementations' : json_getInt(iterList.this: 'number_of_implementations'));
			

			pParms = json_moveobjectinto  ( pRoutine  :  'parms' : json_newArray() ); 
			json_arrayPush(pTree : pRoutine);
		endif;
		json_arrayPush(pParms : iterList.this: JSON_COPY_CLONE);
	enddo;

	return pTree;


end-proc;

// --------------------------------------------------------------------  
dcl-proc buildSwaggerJson;

	dcl-pi *n pointer;
		environment varchar(32) const options(*varsize);
		pRoutines pointer value;
	end-pi;

	dcl-ds iterList   	likeds(json_iterator);  
	dcl-ds iterParms  	likeds(json_iterator);  
	dcl-s pOpenApi  	pointer;
	dcl-s pRoute 		pointer;
	dcl-s pPaths  		pointer;
	dcl-s pParms  		pointer;
	dcl-s pParm   		pointer;
	dcl-s pMethod 		pointer;
	dcl-s pComponents 	pointer;
	dcl-s pSchemas   	pointer;
	dcl-s pPropertyInput pointer;
	dcl-s pPropertyOutput pointer;
	dcl-s pParameters 	pointer;
	dcl-s pParmsInput 	pointer;
	dcl-s pParmsOutput 	pointer;	
	dcl-s ref   		varchar(10) inz('$ref');
	dcl-s Schema   		varchar(32);
	dcl-s Routine 		varchar(32);
	dcl-s resultSets    int(5);
	dcl-s OutputReference varchar(256);

 
	pOpenApi = json_parseString(`{
		"openapi": "3.0.1",
		"info": {
			"title": "${ getServerVar('SERVER_DESCRIPTION') }",
			"version": "${ getServerVar('SERVER_SOFTWARE')}"
		},
		"servers": [
			{
				"url": "${ getServerVar('SERVER_URI') }",
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

	pPaths      = json_moveobjectinto  ( pOpenApi    : 'paths'      : json_newObject() ); 
	pComponents = json_moveobjectinto  ( pOpenApi    : 'components' : json_newObject()); 
	pSchemas    = json_moveobjectinto  ( pComponents : 'schemas'    : json_newObject()); 

	// Now produce the openAPI JSON fro each routine 
	iterList = json_setIterator(pRoutines);  
	dow json_ForEach(iterList) ;  

		schema =  json_getStr(iterList.this:'schema');
		routine = json_getStr(iterList.this:'routine'); 

		resultSets  = json_getInt(iterList.this:'result_sets');
		if resultSets >= 1;
			OutputReference = '"$ref":"#/definitions/ApiResponse"';
		else;
			OutputReference = '"$ref":"#/components/schemas/' + routine + 'Output"';	
		endif; 


		pRoute = json_newObject();
		json_noderename (pRoute : '/' + environment + '/' + schema + '/' + routine);

		pMethod = json_parseString(
		`{
			"tags": [
				"${schema}"
			],
			"operationId": "${routine}",
			"summary": "${  json_getStr(iterList.this:'description') }",
			"requestBody": {
				"content": {
					"application/json": {
						"schema": {
							"${ref}": "#/components/schemas/${routine}Input"
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
		if json_getInt (iterList.this : 'implementations') > 1;
			json_setStr (pMethod  : 'summary' : 'This operation is polymorpich with  ' + 
				json_getStr (iterList.this : 'implementations') + 
				' implementations and can not be executed. Can not decide which to use'); 
		endif;


		if json_getStr (iterList.this:'routine_type') = 'SCALAR' // scalar
		or json_getStr (iterList.this:'routine_type') = 'TABLE' // table
		or resultSets >= 1;                                  // Procedure with result set (open cursor)  
			json_delete ( json_locate(pMethod : 'requestBody'));

			json_moveobjectinto  ( pRoute  :  'get'  : pMethod ); 
			json_nodeInsert ( pPaths  : pRoute : JSON_LAST_CHILD); 
			pParameters = json_moveobjectinto ( pRoute : 'parameters': json_newArray());

			iterParms = json_setIterator(iterList.this:'parms');  
			dow json_ForEach(iterParms) ;  
				if json_getStr (iterParms.this:'parameter_mode') = 'IN'  ;
					json_arrayPush ( pParameters  : swaggerQueryParm (iterParms.this) ); 
				endif;
			enddo;


			pParmsOutput = json_moveobjectinto  ( pSchemas  :  Routine + 'Output' : json_newObject() ); 
			json_setStr(pParmsOutput : 'type' : 'object');
			pPropertyOutput  = json_moveobjectinto  ( pParmsOutput  :  'properties' : json_newObject() ); 

			if json_getStr (iterList.this:'routine_type') = 'SCALAR'; // scalar

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
				json_noderename (pParm : 'result' );
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


			json_moveobjectinto  ( pRoute  :  'post'  : pMethod ); 
			json_nodeInsert ( pPaths  : pRoute : JSON_LAST_CHILD); 

			pParmsInput = json_moveobjectinto  ( pSchemas  :  Routine + 'Input' : json_newObject() ); 
			json_setStr(pParmsInput : 'type' : 'object');
			pPropertyInput  = json_moveobjectinto  ( pParmsInput  :  'properties' : json_newObject() ); 

			if resultSets = 0;
				pParmsOutput = json_moveobjectinto  ( pSchemas  :  Routine + 'Output' : json_newObject() ); 
				json_setStr(pParmsOutput : 'type' : 'object');
				pPropertyOutput  = json_moveobjectinto  ( pParmsOutput  :  'properties' : json_newObject() ); 
			endif;

			iterParms = json_setIterator(iterList.this:'parms');  
			dow json_ForEach(iterParms) ;  
				if json_getStr (iterParms.this:'parameter_mode') = 'IN' 
				or json_getStr (iterParms.this:'parameter_mode') = 'INOUT' ;
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
	enddo;	


	json_moveobjectinto  ( pOpenApi  :  'definitions' : definitions()  ); 

	return (pOpenApi);


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
				"rows": {
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
				"result": {
					"type": "string",
					"default": null
				}
			}
		}
	}`);

end-proc;

// ------------------------------------------------------------------------------------
// swaggerCommonParmmeters
// ------------------------------------------------------------------------------------
dcl-proc swaggerCommonParmmeters;

	dcl-pi *N;
		pSwaggerParm pointer value;
		pMetaParm pointer value;
	end-pi;

	json_setStr ( pSwaggerParm : 'description' : parameterDescription (pMetaParm ));
	json_setStr ( pSwaggerParm : 'type'        : dataTypeJson  (pMetaParm ));
	json_setStr ( pSwaggerParm : 'format'      : dataFormatJson(pMetaParm ));
	json_setBool( pSwaggerParm : 'required'    : json_isnull (pMetaParm : 'DEFAULT') );
	
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
	dcl-s name varchar(32);

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
	dcl-s name varchar(32);
	
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

	dcl-pi *n varchar(32);
		pMetaParm pointer value;
	end-pi;

	dcl-s inputType varchar(32);
	dcl-s numericScale int (5);
	dcl-s numericPrecision int (5);
	 
	inputType = json_getstr (pMetaParm : 'data_type');
	numericScale = json_getint (pMetaParm : 'NUMERIC_SCALE'); // Decimals after 
	numericPrecision = json_getint (pMetaParm : 'NUMERIC_PRECISION');

	select; 
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

	dcl-pi *n varchar(32);
		pMetaParm pointer value;
	end-pi;

	dcl-s inputType varchar(32);
	dcl-s formatString varchar(32);
	dcl-s numericScale int (5);
	dcl-s numericPrecision int (5);
	 
	inputType = json_getstr (pMetaParm : 'data_type');
	numericScale = json_getint (pMetaParm : 'NUMERIC_SCALE'); // Decimals after 
	numericPrecision = json_getint (pMetaParm : 'NUMERIC_PRECISION');

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

	dcl-pi *n varchar(32);
		pMetaParm pointer value;
	end-pi;

	dcl-s inputType varchar(32);
	dcl-s formatString varchar(32);
	dcl-s numericScale int (5);
	dcl-s length int (5);
	 
	inputType = json_getstr (pMetaParm : 'data_type');
	numericScale = json_getint (pMetaParm : 'NUMERIC_SCALE'); // Decimals after 

	if json_isnull (pMetaParm : 'NUMERIC_PRECISION');
		length = json_getint (pMetaParm : 'CHARACTER_MAXIMUM_LENGTH');
	else;
		length = json_getint (pMetaParm : 'NUMERIC_PRECISION');
	endif;


	formatString =  strLower(inputType + '(' + %char(length));
	if numericScale > 0; 
		formatString += ',' + %char(numericScale);
	endif;
	formatString += ')';
	return formatString;

end-proc;


// ------------------------------------------------------------------------------------
// parameter description
// ------------------------------------------------------------------------------------
dcl-proc parameterDescription ;

	dcl-pi *n varchar(1024);
		pMetaParm pointer value;
	end-pi;

	dcl-s  description varchar(1024);
	
	if json_isnull (pMetaParm : 'long_comment' ); 
		description = 	json_getStr ( pMetaParm : 'parameter_name') + ' as ' + dataTypeAsText(pMetaParm);
	else;
		description = 	json_getStr ( pMetaParm : 'long_comment');
	endif; 
	return description;

end-proc;
