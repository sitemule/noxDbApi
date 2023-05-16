<%@ free="*YES" language="RPGLE" runasowner="*YES" owner="QPGMR"%>
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
	
	http://MY_IBM_I:7007/noxdbapi/noxdbapi




	By     Date       PTF     Description
	------ ---------- ------- ---------------------------------------------------
	NLI    25.07.2018         New program
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
	environment = word (url:1:'/');
	schemaName  = word (url:2:'/');
	procName    = word (url:3:'/');

	if  schemaName = 'openapi-meta';
		serveListSchemaProcs (environment : sesGetvar ('schemaName'));
	elseif schemaName = 'static_resources' or procName = ''; 
		serveStatic (schemaName : url);
	else;
		serveProcedureResponse (environment : schemaName : procName);
	endif; 


end-proc;
// --------------------------------------------------------------------  
dcl-proc serveStatic;

	dcl-pi *n;
		schemaName varchar(32);
		url varchar(256);
	end-pi;

	dcl-s i	int(10);
	dcl-s fileName varchar(256); 
	dcl-s staticPath   varchar(256); 
	
	staticPath  = getServerVar('SERVER_ROOT_PATH') + '/static';

	i = %scan (schemaName : url );
	i += %len(schemaName);

	if i >= %len(url);
		sesSetVar  ('schemaName':schemaName);
		fileName = staticPath + '/index.html'; 
	else;		
		fileName = staticPath  + %subst (url : i); 
	endif;

	SetCharset ('charset=utf-8');
	ResponseServeFile (fileName);

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

	SetContentType ('application/json');

	pResponse = runService (environment : schema : procName);
	if (pResponse = *NULL);
		pResponse =  FormatError (
			'Null object returned from service'
		);
	endif;
	
	if json_getStr(pResponse : 'description') <> 'HTML';
		responseWriteJson(pResponse);
		if json_getstr(pResponse : 'success') = 'false';
			msg = json_getstr(pResponse: 'message');
			if msg = '';
				msg = json_getstr(pResponse: 'msg');
			endif;
			setStatus ('500 ' + msg);
			consoleLogjson(pResponse);
		endif;
	endif;
	json_delete(pResponse);

end-proc;
/* -------------------------------------------------------------------- *\  
   get data form request
\* -------------------------------------------------------------------- */
/**********
dcl-proc unpackParms;

	dcl-pi *n pointer;
	end-pi;

	dcl-s pPayload 		pointer;
	dcl-s msg     		varchar(4096);
	dcl-s callback     	varchar(512);


	SetContentType('application/json; charset=utf-8');
	SetEncodingType('*JSON');
	json_setDelimiters('/\@[] ');
	json_sqlSetOptions('{'             + // use dfault connection
		'upperCaseColname: false,   '  + // set option for uppcase of columns names
		'autoParseContent: true,    '  + // auto parse columns predicted to have JSON or XML contents
		'sqlNaming       : false    '  + // use the SQL naming for database.table  or database/table
	'}');

	callback = reqStr('callback');
	if (callback>'');
		responseWrite (callback + '(');
	endif;

	if reqStr('payload') > '';
		pPayload = json_ParseString(reqStr('payload'));
	elseif getServerVar('REQUEST_METHOD') = 'POST';
		pPayload = json_ParseRequest();
	else;
		pPayload = *NULL;
	endif;

	return pPayload;


end-proc;
*****/ 
/* -------------------------------------------------------------------- *\ 
   	run a a microservice call
\* -------------------------------------------------------------------- */
dcl-proc runService export;	

	dcl-pi *n pointer;
		environment   varchar(32);
		schemaName    varchar(32);
		procName	  varchar(128);
	end-pi;
	
	dcl-s pResponse		pointer;	
	dcl-s pPayload      pointer;	
	dcl-s name  		varchar(64);
	dcl-s value  		varchar(32760);
	dcl-s parmList  	varchar(32760);
	dcl-s sqlStmt   	varchar(32760);
	
	dcl-s len 			int(10);
	dcl-ds iterParms  	likeds(json_iterator);


	if schemaName <= '';
		return FormatError (
			'Need schema and procedure'
		);
	endif;

	pPayload = json_ParseRequest();

	// Build parameter from posted payload:
	iterParms = json_SetIterator(pPayload);
	dow json_ForEach(iterParms);
		strAppend (parmlist : ',' : camelToSnakeCase(json_getName(iterParms.this)) + '=>' + strQuot(json_getValue(iterParms.this)));
  	enddo;

	/* 
	// Or if parametres are given atr the URL
	getQryStrList ( name : value : '*FIRST');
	dow name > '';
		strAppend (parmlist : ',' : name + '=>' + strQuot(value));
		getQryStrList ( name : value : '*NEXT');
	enddo;    
	*/ 

	sqlStmt = 'call ' + schemaName + '.' + camelToSnakeCase(procName) + ' (' + parmlist + ')';

	
	pResponse = json_sqlResultSet(
        sqlStmt: // The sql statement,
        1:  // from row,
        -1: // -1=*ALL number of rows
        JSON_META + JSON_CAMEL_CASE
	);

	if json_Error(pResponse);
		consolelog(sqlStmt);
		pResponse= FormatError (
			'Invalid action or parameter: '  
		);
	endif;

	json_delete ( pPayload);
	return pResponse; 

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
		environment varchar(32) const options(*varsize);
		schemaName varchar(32) const options(*varsize);
	end-pi;

	dcl-s pResult   pointer; 
	dcl-s pSwagger  pointer; 
	
	dcl-ds iterList  	likeds(json_iterator);
	dcl-s  prevSchema   	varchar(32);
	dcl-s  prevRoutine 		varchar(32);
 


	pResult = json_sqlResultSet (`
		Select a.routine_schema , a.routine_name, a.long_comment as desc, b.*
		from sysprocs a
		left join  sysparms b 
		on a.specific_schema = b.specific_schema and a.specific_name = b.specific_name 
		where a.routine_schema in ( ${strQuot(schemaName)}) 
		and   a.result_sets = 1 
		and   a.out_parms = 0 ;
	`);

	SetContentType ('application/json');
	pSwagger = buildSwaggerJson (environment : pResult);
	responseWriteJson(pSwagger);

	json_delete (pResult);
	json_delete (pSwagger);

end-proc;
// --------------------------------------------------------------------  
dcl-proc buildSwaggerJson;

	dcl-pi *n pointer;
		environment varchar(32) const options(*varsize);
		pRoutes pointer value;
	end-pi;

	dcl-ds iterList likeds(json_iterator);  
	dcl-s pOpenApi  pointer;
	dcl-s pRoute 	pointer;
	dcl-s pPaths  	pointer;
	dcl-s pParms  	pointer;
	dcl-s pParm   	pointer;
	dcl-s pMethod 	pointer;
	dcl-s pComponents pointer;
	dcl-s pSchemas   pointer;
	dcl-s pProperty pointer;
	dcl-s method 	int(10);
	dcl-s null  	int(10);
	dcl-s path 		varchar(256);
	dcl-s text 		varchar(256);
	dcl-s ref   	varchar(10) inz('$ref');
	dcl-s prevSchemaRoutine varchar(256);
	dcl-s schemaRoutine varchar(256);
	
	dcl-s i 		int(5);

	dcl-s  Schema   	varchar(32);
	dcl-s  Routine 		varchar(32);


	/// SetContentType ('application/json');

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


	// pOpenApi = json_parsefile ('static/openapi-template.json');
	pPaths = json_locate( pOpenApi : 'paths');
	if pPaths = *null;
		pPaths = json_moveobjectinto  ( pOpenApi  :  'paths' : json_newObject() ); 
	endif;

	pComponents = json_moveobjectinto  ( pOpenApi     :  'components' : json_newObject()); 
	pSchemas    = json_moveobjectinto  ( pComponents  :  'schemas' : json_newObject()); 

	// Now produce the menu JSON 
	iterList = json_setIterator(pRoutes);  
	dow json_ForEach(iterList) ;  

		Schema =  snakeToCamelCase (json_getValue(iterList.this:'routine_schema'));
		Routine = snakeToCamelCase (json_getValue(iterList.this:'routine_name')); 
		SchemaRoutine =  Schema + '/' + Routine;

		if  SchemaRoutine <> prevSchemaRoutine;
			prevSchemaRoutine = SchemaRoutine;
			pRoute = json_newObject();
			json_noderename (pRoute : '/' + environment + '/' + SchemaRoutine);
			pMethod = json_parseString(
			`{
				"tags": [
					"${Routine}"
				],
				"operationId": 	"${environment}",
				"summary": "${Routine}",
				"requestBody": {
					"content": {
						"application/json": {
							"schema": {
								"${ref}": "#/components/schemas/${Routine}"
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
									"${ref}": "#/definitions/ApiResponse"
								}
							}
						}
					},
					"403": {
						"description": "No response from service"
					},
					"406": {
						"description": "Combination of parameters raises a conflict"
					},
					"500": {
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
			json_moveobjectinto  ( pRoute  :  'post'  : pMethod ); 
			json_nodeInsert ( pPaths  : pRoute : JSON_LAST_CHILD); 

			pParms = json_moveobjectinto  ( pSchemas  :  Routine : json_newObject() ); 
			json_setStr(pParms : 'type' : 'object');
			pProperty  = json_moveobjectinto  ( pParms  :  'properties' : json_newObject() ); 
			
		endif;

		json_nodeInsert ( pProperty  : swaggerParm (iterList.this)  : JSON_LAST_CHILD); 


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
		}
	}`);

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

	pParm = json_newObject(); 
	json_noderename (pParm : name );
	json_setStr    (pParm : 'name'        : name);
	json_copyValue (pParm : 'description' : pMetaParm : 'long_comment');
	json_setStr    (pParm : 'type'        : dataTypeJson  (json_getstr (pMetaParm : 'data_type')));
	json_setStr    (pParm : 'format'      : dataFormatJson(json_getstr (pMetaParm : 'data_type')));
	json_setBool   (pParm : 'required'    : json_getstr(pMetaParm : 'IS_NULLABLE') <> 'YES' );
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
		inputType varchar(32) const options(*varsize);
	end-pi;

	select; 
		when %len(inputType) >= 3 and %subst ( strLower (inputType) : 1 : 3)  = 'int';
			return 'integer';
		other;
			return 'string';
	endsl;

end-proc;

// ------------------------------------------------------------------------------------
// dataFormatJson
// ------------------------------------------------------------------------------------
dcl-proc dataFormatJson;

	dcl-pi *n varchar(32);
		inputType varchar(32) const options(*varsize);
	end-pi;

	select; 
		when %len(inputType) >= 3 and %subst ( strLower (inputType) : 1 : 3)  = 'int';
			return 'int64';
		other;
			return '';

	endsl;

end-proc;

