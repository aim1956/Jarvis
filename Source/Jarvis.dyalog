﻿:Class Jarvis
⍝ Dyalog Web Service Server
⍝ See https://github.com/dyalog/jarvis/wiki for documentation

    (⎕ML ⎕IO)←1 1

    :Field Public AcceptFrom←⍬    ⍝ IP addresses to accept requests from - empty means accept from any IP address
    :Field Public DenyFrom←⍬      ⍝ IP addresses to refuse requests from - empty means deny none
    :Field Public Port←8080       ⍝ Default port to listen on
    :Field Public BlockSize←10000 ⍝ Conga block size
    :Field Public CodeLocation←#  ⍝ application code location
    :Field Public ConfigFile←''   ⍝ configuration file path (if any)
    :Field Public AppInitFn←'Initialize' ⍝ name of the application "bootstrap" function
    :Field Public ValidateRequestFn←'ValidateRequest' ⍝ name of the request validation function
    :Field Public LoadableFiles←'*.apl*,*.dyalog'  ⍝ file patterns that can be loaded if loading from folder
    :Field Public Logging←1       ⍝ turn logging on/off
    :Field Public HtmlInterface←1 ⍝ allow the HTML interface
    :Field Public Debug←0         ⍝ 0 = all errors are trapped, 1 = stop on an error, 2 = stop on intentional error before processing request
    :Field Public FlattenOutput←0 ⍝ 0=no, 1=yes, 2=yes with notification
    :Field Public ParsePayload←1  ⍝ 1=parse payload based on content-type header
    :Field Public Paradigm←'JSON' ⍝ either 'JSON' or 'REST'
    :Field Public SessionTimeout←0         ⍝ 0 = do not use sessions, ¯1 = no timeout , 0< session timeout time (in minutes)
    :Field Public SessionPollingTime←1     ⍝ how frequently (in minutes) we should poll for timed out sessions
    :Field Public SessionCleanupTime←60    ⍝ how frequently (in minutes) do we clean up timed out session info from _sessionsInfo
    :Field Public SessionStartCommand←'Login'
    :Field Public SessionStopCommand←'Logout'
    :Field Public SessionIdHeader←'Jarvis-SessionID'
    :Field Public SessionInitFn←''
    :Field Public AuthenticateFn←''        ⍝ function name to perform authentication,if empty, no authentication is necessary
    :Field Public IncludeFns←''    ⍝ vector of vectors for function names to be included (can use regex or ? and * as wildcards)
    :Field Public ExcludeFns←''    ⍝ vector of vectors for function names to be excluded (can use regex or ? and * as wildcards)
    :Field Public Secure←0          ⍝ 0 = use HTTP, 1 = use HTTPS
    :Field Public RootCertDir←''    ⍝ Root CA certificate folder
    :Field Public SSLValidation←64  ⍝ request, but do not require a client certificate
    :Field Public ServerCertFile←'' ⍝ public certificate file
    :Field Public ServerKeyFile←''  ⍝ private key file
    :Field Public RESTMethods←'Get,Post,Put,Delete,Patch,Options'
    :Field Public DefaultContentType←'application/json; charset=utf-8'

    :Field Folder←''             ⍝ folder that user supplied in CodeLocation from which to load code
    :Field _configLoaded←0
    :Field _stop←0               ⍝ set to 1 to stop server
    :Field _started←0
    :Field _stopped←1
    :Field _sessionThread←¯1
    :Field _serverThread←¯1
    :Field _taskThreads←⍬
    :Field Public _sessions←⍬   ⍝ vector of session namespaces (remove public after testing!)
    :Field Public _sessionsInfo←0 5⍴'' '' 0 0 0 ⍝ [;1] id [;2] ip addr [;3] creation time [;4] last active time [;5] ref to session
    :Field _includeRegex←''     ⍝ private field compiled regex from IncludeFns
    :Field _excludeRegex←''     ⍝ private compiled regex from ExcludeFns


    ∇ r←Version
      :Access public shared
      r←'Jarvis' '1.0' '2020-01-16'
    ∇

    ∇ r←Config
    ⍝ returns current configuration
      :Access public
      r←↑{⍵(⍎⍵)}¨⎕THIS⍎'⎕NL ¯2.2'
    ∇

    ∇ {r}←Log msg;ts
      :Access public overridable
      :If Logging>0∊⍴msg
          ts←fmtTS ⎕TS
          :If 1=≢⍴msg←⍕msg
          :OrIf 1=⊃⍴msg
              r←ts,' - ',msg
          :Else
              r←ts,∊(⎕UCS 13),msg
          :EndIf
          ⎕←r
      :EndIf
    ∇

    ∇ make
      :Access public
      :Implements constructor
    ∇

    ∇ make1 args;rc;msg;char
      :Access public
      :Implements constructor
    ⍝ args is one of
    ⍝ - a simple character vector which is the name of a configuration file
    ⍝ - a reference to a namespace containing named configuration settings
    ⍝ - a depth 1 or 2 vector of
    ⍝   [1] integer port to listen on
    ⍝   [2] charvec function folder or ref to code location
    ⍝   [3] paradigm to use ('JSON' or 'REST')
      :If char←isChar args ⍝ character argument?  it's a config filename
      :OrIf 9.1={⎕NC⊂,'⍵'}args ⍝ namespace?
          ConfigFile←char/args
          :If 0≠⊃(rc msg)←LoadConfiguration args
              Log'Error loading configuration: ',msg
          :EndIf
      :Else
          (Port CodeLocation Paradigm)←3↑args,(≢,args)↓Port CodeLocation Paradigm [
      :EndIf
    ∇

    ∇ Close
      :Implements destructor
      {0:: ⋄ #.DRC.Close ServerName}⍬
    ∇

    ∇ UpdateRegex arg;t
    ⍝ updates the regular expression for inclusion/exclusion of functions whenever IncludeFns or ExcludeFns is changed
      :Implements Trigger IncludeFns, ExcludeFns
      t←makeRegEx¨(⊂'')~⍨∪,⊆arg.NewValue
      :If arg.Name≡'IncludeFns'
          _includeRegex←t
      :Else
          _excludeRegex←t
      :EndIf
    ∇

    ∇ r←Run args;msg;rc
      :Access shared public
      :Trap 0
          (rc msg)←(r←⎕NEW ⎕THIS args).Start
      :Else
          (r rc msg)←'' ¯1 ⎕DMX.EM
      :EndTrap
      r←(r(rc msg))
    ∇

    ∇ (rc msg)←Start
      :Access public
     
      :If _started
          CheckRC(rc msg)←¯1 'Server thinks it''s already started'
      :EndIf
     
      :If _stop
          CheckRC(rc msg)←¯1 'Server is in the process of stopping'
      :EndIf
     
      CheckRC(rc msg)←LoadConfiguration''
      CheckRC(rc msg)←CheckPort
      CheckRC(rc msg)←LoadConga
      CheckRC(rc msg)←CheckCodeLocation
      :If HtmlInterface>Paradigm match'json'
          Log'HTML interface is currently only available using JSON paradigm'
          HtmlInterface←0
      :EndIf
      CheckRC(rc msg)←StartServer
      Log'DServer started on port ',⍕Port
      Log'Serving code in ',(⍕CodeLocation),(Folder≢'')/' (populated with code from "',Folder,'")'
      :If HtmlInterface
          Log'Click http',(~Secure)↓'s://localhost:',(⍕Port),' to access web interface'
      :EndIf
    ∇

    ∇ (rc msg)←Stop;ts
      :Access public
      :If _stop
          CheckRC(rc msg)←¯1 'Server is already stopping'
      :EndIf
      :If ~_started
          CheckRC(rc msg)←¯1 'Server is not running'
      :EndIf
      ts←⎕AI[3]
      _stop←1
      Log'Stopping server...'
      :While ~_stopped
          :If 10000<⎕AI[3]-ts
              CheckRC(rc msg)←¯1 'Server seems stuck'
          :EndIf
      :EndWhile
      _started←_stop←0
      (rc msg)←0 'Server stopped'
    ∇

    ∇ (rc msg)←Reset
      :Access Public
      ⎕TKILL _serverThread,_sessionThread,_taskThreads
      _sessions←⍬
      _sessionsInfo←0 5⍴0
      _stopped←~_stop←_started←0
      (rc msg)←0 'Server reset (previously set options are still in effect)'
    ∇

    ∇ r←Running
      :Access public
      r←~_stop
    ∇

    ∇ (rc msg)←CheckPort;p
      (rc msg)←3('Invalid port: ',∊⍕Port)
      ExitIf 0=p←⊃⊃(//)⎕VFI⍕Port
      ExitIf{(⍵>32767)∨(⍵<1)∨⍵≠⌊⍵}p
      (rc msg)←0 ''
    ∇

    ∇ (rc msg)←{force}LoadConfiguration value;config;public;set;file
      :Access public
      :If 0=⎕NC'force' ⋄ force←0 ⋄ :EndIf
      (rc msg)←0 ''
      →(_configLoaded>force)⍴0 ⍝ did we already load from AutoStart?
      :Trap Debug↓0
          :If isChar value
              file←ConfigFile
              :If ~0∊⍴value
                  file←value
              :EndIf
              ExitIf 0∊⍴file
              :If ⎕NEXISTS file
                  config←⎕JSON⊃⎕NGET file
              :Else
                  →0⊣(rc msg)←6('Configuation file "',file,'" not found')
              :EndIf
          :ElseIf 9.1={⎕NC⊂,'⍵'}value ⍝ namespace?
              config←value
          :EndIf
          public←⎕THIS⍎'⎕NL ¯2.2' ⍝ find all the public fields in this class
          set←public{⍵/⍨⍵∊⍺}config.⎕NL ¯2
          config{⍎⍵,'←⍺⍎⍵'}¨set
          _configLoaded←1
      :Else
          →0⊣(rc msg)←⎕DMX.EN ⎕DMX.('Error loading configuration: ',EM,(~0∊⍴Message)/' (',Message,')')
      :EndTrap
    ∇

    ∇ (rc msg)←LoadConga;dyalog
      (rc msg)←0 ''
     
      ⍝↓↓↓ if Conga is not found in the workspace, attempt to use the DYALOG environment variable
      ⍝    however, on when using a bound workspaces DYALOG may not be set,
      ⍝    in which case we look in the same folder at the executable
      :If 0=#.⎕NC'Conga'
          dyalog←1⊃1 ⎕NPARTS⊃2 ⎕NQ'.' 'GetCommandLineArgs'
          :Trap 0
              'Conga'#.⎕CY dyalog,'ws/conga'
          :Else
              :If 11 19∧.=⎕DMX.(EN ENX) ⍝ DOMAIN ERROR/WS not found
                  :Trap 0
                      dyalog←⊃1 ⎕NPARTS⊃2 ⎕NQ'.' 'GetCommandLineArgs'
                      'Conga'#.⎕CY dyalog,'ws/conga'
                  :Else
                      (rc msg)←1 'Unable to copy Conga'
                      →0
                  :EndTrap
              :Else
                  (rc msg)←1 'Unable to copy Conga'
                  →0
              :EndIf
          :EndTrap
      :EndIf
     
      :Trap 999 ⍝ Conga.Init signals 999 on error
          #.DRC←#.Conga.Init'Jarvis'
      :Else
          (rc msg)←2 'Unable to initialize Conga'
          →0
      :EndTrap
    ∇

    ∇ (rc msg)←CheckCodeLocation;root;folder;m;res;tmp
      (rc msg)←0 ''
      :If 0∊⍴CodeLocation
          CheckRC(rc msg)←4 'CodeLocation is empty!'
      :EndIf
      :Select ⊃{⎕NC'⍵'}CodeLocation ⍝ need dfn because CodeLocation is a field and will always be nameclass 2
      :Case 9 ⍝ reference, just use it
      :Case 2 ⍝ variable, could be file path or ⍕ of reference from ConfigFile
          :If 326=⎕DR tmp←{0::⍵ ⋄ '#'≠⊃⍵:⍵ ⋄ ⍎⍵}CodeLocation
          :AndIf 9={⎕NC'⍵'}tmp ⋄ CodeLocation←tmp
          :Else
              :If isRelPath CodeLocation
                  :If 'CLEAR WS'≡⎕WSID
                      root←⊃1 ⎕NPARTS''
                  :Else
                      root←⊃1 ⎕NPARTS ⎕WSID
                  :EndIf
              :Else
                  root←''
              :EndIf
              folder←∊1 ⎕NPARTS root,CodeLocation
              :Trap 0
                  :If 1≠1 ⎕NINFO folder
                      CheckRC(rc msg)←5('CodeLocation "',(∊⍕CodeLocation),'" is not a folder.')
                  :EndIf
              :Case 22 ⍝ file name error
                  CheckRC(rc msg)←6('CodeLocation "',(∊⍕CodeLocation),'" was not found.')
              :Else    ⍝ anything else
                  CheckRC(rc msg)←7((⎕DMX.(EM,' (',Message,') ')),'occured when validating CodeLocation "',(∊⍕CodeLocation),'"')
              :EndTrap
              CodeLocation←⍎'CodeLocation'#.⎕NS''
              (rc msg)←CodeLocation LoadFromFolder Folder←folder
          :EndIf
      :Else
          CheckRC(rc msg)←5 'CodeLocation is not valid, it should be either a namespace/class reference or a file path'
      :EndSelect
     
      :If ~0∊⍴AppInitFn  ⍝ initialization function specified?
          :If 3=CodeLocation.⎕NC AppInitFn ⍝ does it exist?
              :If 1 0 0≡⊃CodeLocation.⎕AT AppInitFn ⍝ result-returning niladic?
                  res←,⊆CodeLocation⍎AppInitFn        ⍝ run it
                  CheckRC(rc msg)←2↑res,(⍴res)↓¯1('"',(⍕CodeLocation),'.',AppInitFn,'" did not return a 0 return code')
              :Else
                  CheckRC(rc msg)←8('"',(⍕CodeLocation),'.',AppInitFn,'" is not a niladic result-returning function')
              :EndIf
          :EndIf
      :EndIf
     
      Validate←{0} ⍝ dummy validation function
     
      :If ~0∊⍴ValidateRequestFn  ⍝ Request validation function specified?
          :If 3=CodeLocation.⎕NC ValidateRequestFn ⍝ does it exist?
              :If 1 1 0≡⊃CodeLocation.⎕AT ValidateRequestFn ⍝ result-returning monadic?
                  Validate←CodeLocation⍎ValidateRequestFn
              :Else
                  CheckRC(rc msg)←8('"',(⍕CodeLocation),'.',ValidateRequestFn,'" is not a monadic result-returning function')
              :EndIf
          :EndIf
      :EndIf
    ∇

    Exists←{0:: ¯1 (⍺,' "',⍵,'" is not a valid folder name.') ⋄ ⎕NEXISTS ⍵:0 '' ⋄ ¯1 (⍺,' "',⍵,'" was not found.')}

    ∇ (rc msg)←StartServer;r;cert;secureParams;accept;deny
      msg←'Unable to start server'
      accept←'Accept'ipRanges AcceptFrom
      deny←'Deny'ipRanges DenyFrom
      secureParams←⍬
      :If Secure
          :If ~0∊⍴RootCertDir ⍝ on Windows not specifying RootCertDir will use MS certificate store
              CheckRC(rc msg)←'RootCertDir'Exists RootCertDir
              CheckRC(rc msg)←{(⊃⍵)'Error setting RootCertDir'}#.DRC.SetProp'.' 'RootCertDir'RootCertDir
          :EndIf
          CheckRC(rc msg)←'ServerCertFile'Exists ServerCertFile
          CheckRC(rc msg)←'ServerKeyFile'Exists ServerKeyFile
          cert←⊃#.DRC.X509Cert.ReadCertFromFile ServerCertFile
          cert.KeyOrigin←'DER'ServerKeyFile
          secureParams←('X509'cert)('SSLValidation'SSLValidation)
      :EndIf
      :If 98 10048∊⍨rc←1⊃r←#.DRC.Srv'' ''Port'http'BlockSize,secureParams,accept,deny ⍝ 98=Linux, 10048=Windows
          CheckRC(rc msg)←10('Server could not start - port ',(⍕Port),' is already in use')
      :ElseIf 0=rc
          (_started _stopped)←1 0
          ServerName←2⊃r
          {}#.DRC.SetProp'.' 'EventMode' 1 ⍝ report Close/Timeout as events
          {}#.DRC.SetProp ServerName'FIFOMode' 0
          {}#.DRC.SetProp ServerName'DecodeBuffers' 15 ⍝ 15 ⍝ decode all buffers
          Connections←#.⎕NS''
          InitSessions
          RunServer
          msg←''
      :Else
          CheckRC rc'Error creating server'
      :EndIf
    ∇

    ∇ RunServer
      _serverThread←Server&⍬
    ∇

    ∇ Server arg;wres;rc;obj;evt;data;ref;ip;congaError
     
      :If 0≠#.DRC.⎕NC⊂'Error' ⋄ congaError←#.DRC.Error ⍝ Conga 3.2 moved Error into the library instance
      :Else ⋄ congaError←#.Conga.Error                 ⍝ Prior to 3.2 Error was in the namespace
      :EndIf
     
      :While ~_stop
          wres←#.DRC.Wait ServerName 2500 ⍝ Wait for WaitTimeout before timing out
          ⍝ wres: (return code) (object name) (command) (data)
          (rc obj evt data)←4↑wres
          :Select rc
          :Case 0
              :Select evt
              :Case 'Error'
                  _stop←ServerName≡obj
                  :If 0≠4⊃wres
                      Log'RunServer: DRC.Wait reported error ',(⍕congaError 4⊃wres),' on ',(2⊃wres),GetIP obj
                  :EndIf
                  Connections.⎕EX obj
     
              :Case 'Connect'
                  obj Connections.⎕NS''
                  (Connections⍎obj).IP←2⊃2⊃#.DRC.GetProp obj'PeerAddr'
     
              :CaseList 'HTTPHeader' 'HTTPTrailer' 'HTTPChunk' 'HTTPBody'
                  _taskThreads←⎕TNUMS∩_taskThreads,(Connections⍎obj){t←⍺ HandleRequest ⍵ ⋄ ⎕EX t/⍕⍺}&wres
     
              :CaseList 'Closed' 'Timeout'
     
              :Else ⍝ unhandled event
                  Log'Unhandled Conga event:'
                  Log⍕wres
              :EndSelect ⍝ evt
     
          :Case 1010 ⍝ Object Not found
             ⍝ Log'Object ''',ServerName,''' has been closed - Web Server shutting down'
              →0
     
          :Else
              Log'Conga wait failed:'
              Log wres
          :EndSelect ⍝ rc
      :EndWhile
      {}#.DRC.Close ServerName
      ⎕TKILL _sessionThread~0
      _stopped←1
    ∇

    :Section RequestHandling
    ∇ r←ns HandleRequest req;data;evt;obj;rc;cert
      (rc obj evt data)←req
      r←0
      :Hold obj
          :Select evt
          :Case 'HTTPHeader'
              ns.Req←⎕NEW Request data
              ns.Req.PeerCert←''
              ns.Req.PeerAddr←2⊃2⊃#.DRC.GetProp obj'PeerAddr'
              :If ~0∊⍴DefaultContentType
                  'content-type'ns.Req.SetHeader DefaultContentType
              :EndIf
     
              :If Secure
                  (rc cert)←2↑#.DRC.GetProp obj'PeerCert'
                  :If rc=0
                      ns.Req.PeerCert←cert
                  :Else
                      ns.Req.PeerCert←'Could not obtain certificate'
                  :EndIf
              :EndIf
     
          :Case 'HTTPBody'
              ns.Req.ProcessBody data
          :Case 'HTTPChunk'
              ns.Req.ProcessChunk data
          :Case 'HTTPTrailer'
              ns.Req.ProcessTrailer data
          :EndSelect
     
          :If ns.Req.Complete
              :If ns.Req.Response.Status=200
                  :If Debug=2  ⍝ framework debug
                      ∘∘∘
                  :EndIf
     
                  :Select lc Paradigm
                  :Case 'json'
                      :If HtmlInterface∧~(⊂ns.Req.Page)∊(,'/')'/favicon.ico'
                          →0⍴⍨'(Request method should be POST)'ns.Req.Fail 405×'post'≢ns.Req.Method
                          →0⍴⍨'(Bad URI)'ns.Req.Fail 400×'/'≠⊃ns.Req.Page
                          →0⍴⍨'(Content-Type should be application/json)'ns.Req.Fail 400×(0∊⍴ns.Req.Body)⍱'application/json'begins lc ns.Req.GetHeader'content-type'
                      :EndIf
                      rc←HandleJSONRequest ns
                  :Case 'rest'
                      rc←HandleRESTRequest ns
                  :EndSelect
                  :If 0≠rc
                      {}#.DRC.Close obj
                      Connections.⎕EX obj
                      →0
                  :EndIf
              :EndIf
              r←obj Respond ns.Req
          :EndIf
      :EndHold
    ∇

    ∇ r←HandleJSONRequest ns;payload;fn;resp;valence;nc
      r←0
      ExitIf HtmlInterface∧ns.Req.Page≡'/favicon.ico'
     
      :If 0∊⍴fn←1↓'.'@('/'∘=)ns.Req.Page
          ExitIf('No function specified')ns.Req.Fail 400×~HtmlInterface∧'get'≡ns.Req.Method
          ns.Req.Response.Headers←1 2⍴'Content-Type' 'text/html'
          ns.Req.Response.JSON←HtmlPage
          →0
      :EndIf
     
      ExitIf'(Cannot accept query parameters)'ns.Req.Fail 400×~0∊⍴ns.Req.QueryParams
     
      :Trap Debug↓0
          ns.Req.(Payload←{0∊⍴⍵:⍵ ⋄ 0 ⎕JSON ⍵}Body)
      :Else
          ExitIf'Could not parse payload as JSON'ns.Req.Fail 400
      :EndTrap
     
      ExitIf~fn CheckAuthentication ns.Req
     
      ExitIf('Invalid function "',fn,'"')ns.Req.Fail CheckFunctionName fn
      ExitIf('Invalid function "',fn,'"')ns.Req.Fail 404×3≠⌊|{0::0 ⋄ CodeLocation.⎕NC⊂⍵}fn  ⍝ is it a function?
      valence←|⊃CodeLocation.⎕AT fn
      ExitIf('"',fn,'" is not a monadic result-returning function')ns.Req.Fail 400×1 1 0≢×valence
     
      :Trap Debug↓0
          :If 2=valence[2] ⍝ dyadic
              resp←ns.Req(CodeLocation⍎fn)ns.Req.Payload
          :Else
              resp←(CodeLocation⍎fn)ns.Req.Payload
          :EndIf
      :Else
          ExitIf(⍕⎕DMX.(EM Message))ns.Req.Fail 500
      :EndTrap
     
      :Trap Debug↓0
          ns.Req.Response.JSON←⎕UCS'UTF-8'⎕UCS 1 ⎕JSON resp
      :Else
          :If FlattenOutput>0
              :Trap 0
                  ns.Req.Response.JSON←⎕UCS'UTF-8'⎕UCS JSON resp
                  :If FlattenOutput=2
                      Log'"',fn,'" returned data of rank > 1'
                  :EndIf
              :Else
                  ExitIf'Could not format result payload as JSON'ns.Req.Fail 500
              :EndTrap
          :Else
              ExitIf'Could not format result payload as JSON'ns.Req.Fail 500
          :EndIf
      :EndTrap
    ∇

    ∇ r←HandleRESTRequest ns;fn;method;ind;exec;valence;ct
      r←0
     
      :If 0∊⍴fn←1↓'.'@('/'∘=)ns.Req.Page
          ExitIf'No resource specified'ns.Req.Fail 400
      :EndIf
     
      :If ParsePayload
          :Trap Debug↓0
              :Select ct←lc ns.Req.GetHeader'content-type'
              :Case 'application/json'
                  ns.Req.(Payload←0 ⎕JSON Body)
              :Case 'application/xml'
                  ns.Req.(Payload←⎕XML Body)
              :EndSelect
          :Else
              ExitIf('Unable to parse request body as ',ct)ns.Req.Fail 400
          :EndTrap
      :EndIf
     
      ExitIf~fn CheckAuthentication ns.Req
     
      method←lc ns.Req.Method
     
      ind←RESTMethods[;1]⍳⊆method
      ExitIf'Method not allowed'ns.Req.Fail 405×(≢RESTMethods)<ind
      exec←⊃RESTMethods[ind;2]
      ExitIf'Not implemented'ns.Req.Fail 501×0∊⍴exec
     
      :Trap Debug↓0
          (CodeLocation⍎exec)ns
      :Else
          ExitIf(⍕⎕DMX.(EM Message))ns.Req.Fail 500
      :EndTrap
    ∇

    ∇ r←fn CheckAuthentication req;id
    ⍝ Check request authentication
    ⍝ r is 1 if request processing can continue (0 is returned if new session is created)
      :If 0=SessionTimeout ⍝ not using sessions
          r←Authenticate req
      :Else
          :If 0∊⍴id←req.GetHeader SessionIdHeader ⍝ no session ID?
              :If SessionStartCommand≡fn ⍝ is this a session start request?
              :AndIf r←Authenticate req ⍝ do we require authentication?
                  CreateSession req
              :EndIf
          :Else ⍝ check session id
              r←req CheckSession id
          :EndIf
      :EndIf
    ∇

    ∇ r←Authenticate req
      :If ~r←0∊⍴AuthenticateFn ⍝ do we have an authentication function?
          :If 3=CodeLocation.⎕NC AuthenticateFn ⍝ and it exists
              :Trap r←0
                  :If r←~(CodeLocation⍎AuthenticateFn)req
                      'Unauthorized'req.Fail 401
                      'WWW-Authenticate'req.SetHeader'Basic realm="Jarvis", charset="UTF-8"'
                  :EndIf
              :Else ⍝ Authenticate errored
                  (⎕DMX.EM,' occured during authentication')req.Fail 500
              :EndTrap
          :Else
              'Authentication function not found'req.Fail 500
          :EndIf
      :EndIf
    ∇


    ∇ r←obj Respond req;status;z;res
      res←req.Response
      status←(⊂'HTTP/1.1'),res.((⍕Status)StatusText)
      :If 2≠⌊0.01×res.Status ⍝ if failed response, replace headers
          res.Headers←1 2⍴'content-type' 'text/html'
      :EndIf
      res.Headers⍪←'server'(⊃Version)
      res.Headers⍪←'date'(2⊃#.DRC.GetProp'.' 'HttpDate')
      :If 0≠1⊃z←#.DRC.Send obj(status,res.Headers res.JSON)1
          Log'Conga error when sending response',GetIP obj
          Log⍕z
      :EndIf
      Connections.⎕EX obj
      r←1
    ∇

    :EndSection ⍝ Request Handling

    ∇ ip←GetIP objname
      ip←{6::'' ⋄ ' (IP Address ',(⍕(Connections⍎⍵).IP),')'}objname
    ∇

    ∇ r←CheckFunctionName fn
    ⍝ checks the requested function name and returns
    ⍝    0 if the function is allowed
    ⍝  404 (not found) if the list of allowed functions is non-empty and fn is not in the list
    ⍝  403 (forbidden) if fn is in the list of disallowed functions
      :Access public
      r←0
      fn←,⊆fn
      ExitIf r←403×fn∊AppInitFn ValidateRequestFn AuthenticateFn SessionStartCommand SessionStopCommand SessionInitFn
      :If ~0∊⍴_includeRegex
          ExitIf r←404×0∊⍴(_includeRegex ⎕S'%')fn
      :EndIf
      :If ~0∊⍴_excludeRegex
          r←403×~0∊⍴(_excludeRegex ⎕S'%')fn
      :EndIf
    ∇

    :class Request
        :Field Public Instance Complete←0        ⍝ do we have a complete request?
        :Field Public Instance Input←''
        :Field Public Instance Host←''           ⍝ host header field
        :Field Public Instance Headers←0 2⍴⊂''   ⍝ HTTPRequest header fields (plus any supplied from HTTPTrailer event)
        :Field Public Instance Method←''         ⍝ HTTP method (GET, POST, PUT, etc)
        :Field Public Instance Page←''           ⍝ Requested URI
        :Field Public Instance Body←''           ⍝ body of the request
        :Field Public Instance Payload←''        ⍝ parsed (if JSON or XML) payload
        :Field Public Instance PeerAddr←'unknown'⍝ client IP address
        :Field Public Instance PeerCert←0 0⍴⊂''  ⍝ client certificate
        :Field Public Instance HTTPVersion←''
        :Field Public Instance Response
        :Field Public Instance Session←⍬
        :Field Public Instance QueryParams←0 2⍴0
        :Field Public Instance UserID←''
        :Field Public Instance Password←''

        GetFromTable←{(⍵[;1]⍳⊂,⍺)⊃⍵[;2],⊂''}
        split←{p←(⍺⍷⍵)⍳1 ⋄ ((p-1)↑⍵)(p↓⍵)} ⍝ Split ⍵ on first occurrence of ⍺
        lc←0∘(819⌶)

        ∇ {r}←{a}Fail w
          :Access public
          r←a{⍺←''
              0≠⍵:1⊣('Bad Request',(3×0∊⍴⍺)↓' - ',⍺)SetStatus ⍵
              ⍵}w
        ∇

        ∇ make args;query;origin;length
          :Access public
          :Implements constructor
          (Method Input HTTPVersion Headers)←args
          Headers[;1]←lc Headers[;1]  ⍝ header names are case insensitive
          Method←lc Method
         
          Response←⎕NS''
          Response.(Status StatusText)←200 'OK'
          Response.Headers←0 2⍴'' ''
         
          Host←GetHeader'host'
          (Page query)←URLDecode¨'?'split Input
          QueryParams←2↑[2]↑'='(≠⊆⊢)¨'&'(≠⊆⊢)query
          Complete←('get'≡Method)∨(length←GetHeader'content-length')≡,'0' ⍝ we're a GET or 0 content-length
          Complete∨←(0∊⍴length)>∨/'chunked'⍷GetHeader'transfer-encoding' ⍝ or no length supplied and we're not chunked
          :If 'basic '≡lc 6↑auth←GetHeader'authorization'
              (UserID Password)←':'split Base64Decode 6↓auth
          :EndIf
        ∇

        ∇ ProcessBody args
          :Access public
          Body←args
          Complete←1
        ∇

        ∇ ProcessChunk args
          :Access public
        ⍝ args is [1] chunk content [2] chunk-extension name/value pairs (which we don't expect and won't process)
          Body,←1⊃args
        ∇

        ∇ ProcessTrailer args;inds;mask
          :Access public
          args[;1]←lc args[;1]
          mask←(≢Headers)≥inds←Headers[;1]⍳args[;1]
          Headers[mask/inds;2]←mask/args[;2]
          Headers⍪←(~mask)⌿args
          Complete←1
        ∇

        ∇ r←URLDecode r;rgx;rgxu;i;j;z;t;m;⎕IO;lens;fill
          :Access public shared
        ⍝ Decode a Percent Encoded string https://en.wikipedia.org/wiki/Percent-encoding
          ⎕IO←0
          ((r='+')/r)←' '
          rgx←'[0-9a-fA-F]'
          rgxu←'%[uU]',(4×⍴rgx)⍴rgx ⍝ 4 characters
          r←(rgxu ⎕R{{⎕UCS 16⊥⍉16|'0123456789ABCDEF0123456789abcdef'⍳⍵}2↓⍵.Match})r
          :If 0≠⍴i←(r='%')/⍳⍴r
          :AndIf 0≠⍴i←(i≤¯2+⍴r)/i
              z←r[j←i∘.+1 2]
              t←'UTF-8'⎕UCS 16⊥⍉16|'0123456789ABCDEF0123456789abcdef'⍳z
              lens←⊃∘⍴¨'UTF-8'∘⎕UCS¨t  ⍝ UTF-8 is variable length encoding
              fill←i[¯1↓+\0,lens]
              r[fill]←t
              m←(⍴r)⍴1 ⋄ m[(,j),i~fill]←0
              r←m/r
          :EndIf
        ∇

          base64←{⎕IO ⎕ML←0 1              ⍝ from dfns workspace - Base64 encoding and decoding as used in MIME.
              chars←'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
              bits←{,⍉(⍺⍴2)⊤⍵}             ⍝ encode each element of ⍵ in ⍺ bits, and catenate them all together
              part←{((⍴⍵)⍴⍺↑1)⊂⍵}          ⍝ partition ⍵ into chunks of length ⍺
              0=2|⎕DR ⍵:2∘⊥∘(8∘↑)¨8 part{(-8|⍴⍵)↓⍵}6 bits{(⍵≠64)/⍵}chars⍳⍵  ⍝ decode a string into octets
              four←{                       ⍝ use 4 characters to encode either
                  8=⍴⍵:'=='∇ ⍵,0 0 0 0     ⍝   1,
                  16=⍴⍵:'='∇ ⍵,0 0         ⍝   2
                  chars[2∘⊥¨6 part ⍵],⍺    ⍝   or 3 octets of input
              }
              cats←⊃∘(,/)∘((⊂'')∘,)        ⍝ catenate zero or more strings
              cats''∘four¨24 part 8 bits ⍵
          }

        ∇ r←{cpo}Base64Encode w
        ⍝ Base64 Encode
        ⍝ Optional cpo (code points only) suppresses UTF-8 translation
        ⍝ if w is numeric (single byte integer), skip any conversion
          :Access public shared
          :If 83=⎕DR w ⋄ r←base64 w
          :ElseIf 0=⎕NC'cpo' ⋄ r←base64'UTF-8'⎕UCS w
          :Else ⋄ r←base64 ⎕UCS w
          :EndIf
        ∇

        ∇ r←{cpo}Base64Decode w
        ⍝ Base64 Decode
        ⍝ Optional cpo (code points only) suppresses UTF-8 translation
          :Access public shared
          :If 0=⎕NC'cpo' ⋄ r←'UTF-8'⎕UCS base64 w
          :Else ⋄ r←⎕UCS base64 w
          :EndIf
        ∇

        ∇ r←{table}GetHeader name
          :Access Public Instance
          :If 0=⎕NC'table' ⋄ table←Headers ⋄ :EndIf
          r←(lc name)GetFromTable table
        ∇

        ∇ name SetHeader value
          :Access Public Instance
          Response.Headers⍪←name value
        ∇

        ∇ {statusText}SetStatus status
          :Access public instance
          :If status≠0
              :If 0=⎕NC'statusText' ⋄ statusText←'' ⋄ :EndIf
              Response.(Status StatusText)←status statusText
          :EndIf
        ∇

    :EndClass

    :Section SessionHandler

    ∇ InitSessions
    ⍝ initialize session handling
      :If 0≠SessionTimeout ⍝ are we using sessions?
          _sessions←⍬
          _sessionsInfo←0 5⍴0 ⍝ [;1] id, [;2] IP address, [;3] creation [;4] last active, [;5] ref to session
          ⎕RL←⍬
          :If 0<SessionTimeout ⍝ is there a timeout set?  0> means no timeout and sessions are managed by the application
              _sessionThread←SessionMonitor&SessionTimeout
          :EndIf
      :EndIf
    ∇

    ∇ SessionMonitor timeout;expired;dead
      :Repeat
          :If 0<≢_sessionsInfo
              :Hold 'Sessions'
                  :If ∨/expired←SessionTimeout IsExpired _sessionsInfo[;4] ⍝ any expired?
                      _sessions~←expired/_sessionsInfo[;5] ⍝ remove from sessions list
                      (expired/_sessionsInfo[;5])←⊂⍬      ⍝ remove reference from _sessionsInfo
                  :EndIf
                  :If ∨/dead←SessionCleanupTime IsExpired _sessionsInfo[;4] ⍝ any expired sessions need their info removed?
                      _sessionsInfo⌿⍨←~dead ⍝ remove from _sessionsInfo
                  :EndIf
              :EndHold
          :EndIf
          {}⎕DL timeout×60
      :EndRepeat
    ∇

    MakeSessionId←{⎕IO←0 ⋄((0(819⌶)⎕A),⎕A,⎕D)[(?20⍴62),5↑1↓⎕TS]}
    IsExpired←{⍺≤0: 0 ⋄ (Now-⍵)>(⍺×60000)÷86400000}

    ∇ r←DateToIDNX ts
    ⍝ Date to IDN eXtended
      :Access public shared
      r←(2 ⎕NQ'.' 'DateToIDN'(3↑ts))+(0 60 60 1000⊥¯4↑7↑ts)÷86400000
    ∇

    ∇ CreateSession req;ref;now;id;ts
    ⍝ called in response to SessionStartCommand request, e.g. http://mysite.com/CreateSession
      id←MakeSessionId''
      now←Now
      :Hold 'Sessions'
          _sessions,←ref←⎕NS''
          _sessionsInfo⍪←id req.PeerAddr now now ref
      :EndHold
      SessionIdHeader req.SetHeader id
      :If ~0∊⍴SessionInitFn
          :If 3=CodeLocation.⎕NC SessionInitFn
              'Session initialization failed'req.SetStatus 500×{0::1 ⋄ 0⊣CodeLocation⍎SessionInitFn,' ⍵'}ref
          :Else
              ('Session initialization function "',SessionInitFn,'" not found')req.SetStatus 500
          :EndIf
      :EndIf
      'No Content'req.SetStatus 204
    ∇

    ∇ r←KillSession id;ind
    ⍝ forcibly kill a session
    ⍝ r is 1 if session was killed, 0 if not found
      :Hold 'Sessions'
          :If r←(≢_sessionsInfo)≥ind←_sessionsInfo[;1]⍳⊆id
              _sessions~←_sessionsInfo[ind;5]
              _sessionsInfo⌿⍨←ind≠⍳≢_sessionsInfo
          :EndIf
      :EndHold
    ∇

    ∇ req TimeoutSession ind
    ⍝ assumes :Hold 'Sessions' is set in calling environment
    ⍝ removes session from _sessions and marks it as time out in _sessionsInfo
      _sessions~←_sessionsInfo[ind;5]
      _sessionsInfo⌿←ind≠⍳≢_sessionsInfo
      'Session Timed Out'req.Fail 408
    ∇

    ∇ r←req CheckSession id;ind;session;timedOut
      r←0
      :Hold 'Sessions'
          ind←_sessionsInfo[;1]⍳⊂id
          ExitIf'Invalid Session ID'req.Fail 403×ind>≢_sessionsInfo
          :If SessionTimeout>0
              :If timedOut←0∊⍴session←⊃_sessionsInfo[ind;5] ⍝ already timed out?
              :ElseIf timedOut←(Now-_sessionsInfo[ind;4])>(SessionTimeout×60000)÷86400000
                  _sessions~←_sessionsInfo[ind;5]
              :EndIf
              :If timedOut
                  _sessionsInfo←_sessionsInfo[ind~⍨⍳≢_sessionsInfo;]
                  ExitIf'Session Timed Out'req.Fail 408
              :EndIf
          :EndIf
          SessionIdHeader req.SetHeader id
          _sessionsInfo[ind;4]←Now
          req.Session←session
          r←1
      :EndHold
    ∇

    :EndSection

    :Section Utilities

    ExitIf←→⍴∘0
    CheckRC←ExitIf(0∘≠⊃)

    ∇ r←Now
      :Access public shared
      r←DateToIDNX ⎕TS
    ∇

    ∇ r←flatten w
    ⍝ "flatten" arrays of rank>1
    ⍝ JSON cannot represent arrays of rank>1, so we "flatten" them into vectors of vectors (of vectors...)
      :Access public shared
      r←{(↓⍣(¯1+≢⍴⍵))⍵}w
    ∇

    ∇ r←fmtTS ts
      :Access public shared
      r←,'G⊂9999/99/99 @ 99:99:99⊃'⎕FMT 100⊥6↑ts
    ∇

    ∇ r←a splitOn w
      :Access public shared
      r←a⊆⍨~a∊w
    ∇

    ∇ r←type ipRanges string;ranges
      :Access public shared
      r←''
      :Select ≢ranges←{('.'∊¨⍵){⊂1↓∊',',¨⍵}⌸⍵}string splitOn','
      :Case 0
          →0
      :Case 1
          r←,⊂((1+'.'∊⊃ranges)⊃'IPV6' 'IPV4')(⊃ranges)
      :Case 2
          r←↓'IPV4' 'IPV6',⍪ranges
      :EndSelect
      r←⊂(('Accept' 'Deny'⍳⊂type)⊃'AllowEndPoints' 'DenyEndPoints')r
    ∇

    ∇ r←leaven w
    ⍝ "leaven" JSON vectors of vectors (of vectors...) into higher rank arrays
      :Access public shared
      r←{
          0 1∊⍨≡⍵:⍵
          1=≢∪≢¨⍵:↑∇¨⍵
          ⍵
      }w
    ∇

    ∇ r←isRelPath w
    ⍝ is path w a relative path?
      r←{{~'/\'∊⍨(⎕IO+2×('Win'≡3↑⊃#.⎕WG'APLVersion')∧':'∊⍵)⊃⍵}3↑⍵}w
    ∇

    lc←0∘(819⌶) ⍝ lower case
    nocase←{(lc ⍺)⍺⍺ lc ⍵}
    begins←{⍺≡(⍴⍺)↑⍵}
    match←{⍺ (≡nocase) ⍵}
    sins←{0∊⍴⍺:⍵ ⋄ ⍺} ⍝ set if not set

    ∇ r←SourceFile;class
      :Access public shared
      :If 0∊⍴r←4⊃5179⌶class←⊃∊⎕CLASS ⎕THIS
          r←{6::'' ⋄ ∊1 ⎕NPARTS ⍵⍎'SALT_Data.SourceFile'}class
      :EndIf
    ∇

    ∇ r←makeRegEx w
    ⍝ convert a simple search using ? and * to regex
      :Access public shared
      r←{0∊⍴⍵:⍵
          ¯1=⎕NC('A'@(∊∘'?*'))r←⍵:('/'=⊣/⍵)↓(¯1×'/'=⊢/⍵)↓⍵   ⍝ already regex? (remove leading/trailing '/'
          r←∊(⊂'\.')@('.'=⊢)r  ⍝ escape any periods
          r←'.'@('?'=⊢)r       ⍝ ? → .
          r←∊(⊂'.*')@('*'=⊢)r  ⍝ * → .*
          '^',r,'$'            ⍝ add start and end of string markers
      }w
    ∇

    ∇ (rc msg)←{root}LoadFromFolder path;type;name;nsName;parts;ns;files;folders;file;folder;ref;r;m;findFiles;pattern
      :Access public
    ⍝ Loads an APL "project" folder
      (rc msg)←0 ''
      root←{6::⍵ ⋄ root}#
      findFiles←{⊃{(⍵=2)/⍺}/0 1(⎕NINFO⍠1)∊1 ⎕NPARTS path,'/',⍵}
      files←''
      :For pattern :In ','(≠⊆⊢)LoadableFiles
          files,←findFiles pattern
      :EndFor
      folders←⊃{(⍵=1)/⍺}/0 1(⎕NINFO⍠1)∊1 ⎕NPARTS path,'/*'
      :For file :In files
          2 root.⎕FIX'file://',file
      :EndFor
      :For folder :In folders
          nsName←2⊃1 ⎕NPARTS folder
          ref←0
          :Select root.⎕NC⊂nsName
          :Case 9.1 ⍝ namespace
              ref←root⍎nsName
          :Case 0   ⍝ not defined
              ref←⍎nsName root.⎕NS''
          :Else     ⍝ oops
              msg,←'"',folder,'" cannot be mapped to a valid namespace name',⎕UCS 13
          :EndSelect
          :If ref≢0
              (r m)←ref LoadFromFolder folder
              r←rc⌈r
              msg,←m
          :EndIf
      :EndFor
      msg←¯1↓msg
    ∇
    :EndSection

    :Section JSON

    ∇ r←{debug}JSON array;typ;ic;drop;ns;preserve;quote;qp;eval;t;n
    ⍝ JSONify namespaces/arrays with elements of rank>1
      :Access public shared
      debug←{6::⍵ ⋄ debug}0
      array←{(↓⍣(¯1+≢⍴⍵))⍵}array
      :Trap debug↓0
          :If {(0∊⍴⍴⍵)∧0=≡⍵}array ⍝ simple?
              r←{⎕PP←34 ⋄ (2|⎕DR ⍵)⍲∨/b←'¯'=r←⍕⍵:r ⋄ (b/r)←'-' ⋄ r}array
              →0⍴⍨2|typ←⎕DR array ⍝ numbers?
              :Select ⎕NC⊂'array'
              :CaseList 9.4 9.2
                  ⎕SIGNAL(⎕THIS≡array)/⊂('EN' 11)('Message' 'Array cannot be a class')
              :Case 9.1
                  r←,'{'
                  :For n :In n←array.⎕NL-2 9.1
                      r,←'"',(∊((⊂'\'∘,)@(∊∘'"\'))n),'":' ⍝ name
                      r,←(debug JSON array⍎n),','  ⍝ the value
                  :EndFor
                  r←'}',⍨(-1<⍴r)↓r
              :Else ⋄ r←1⌽'""',escapedChars array
              :EndSelect
          :Else ⍝ is not simple (array)
              r←'['↓⍨ic←isChar array
              :If 0∊⍴array ⋄ →0⊣r←(1+ic)⊃'[]' '""'
              :ElseIf ic ⋄ r,←1⌽'""',escapedChars,array ⍝ strings are displayed as such
              :ElseIf 2=≡array
              :AndIf 0=≢⍴array
              :AndIf isChar⊃array ⋄ →0⊣r←⊃array
              :Else ⋄ r,←1↓∊',',¨debug JSON¨,array
              :EndIf
              r,←ic↓']'
          :EndIf
      :Else ⍝ :Trap 0
          (⎕SIGNAL/)⎕DMX.(EM EN)
      :EndTrap
    ∇

    isChar←{0 2∊⍨10|⎕DR ⍵}
      escapedChars←{
          str←⍵
          ~1∊b←str∊fnrbt←'"\/',⎕UCS 12 10 13 8 9:str
          (b/str)←'\"' '\\' '\/' '\f' '\n' '\r' '\b' '\t'[fnrbt⍳b/str]
          str
      }

    :EndSection

    :Section HTML
    ∇ r←ScriptFollows
      :Access public shared
      r←{⍵/⍨'⍝'≠⊃¨⍵}{1↓¨⍵/⍨∧\'⍝'=⊃¨⍵}{⍵{((∨\⍵)∧⌽∨\⌽⍵)/⍺}' '≠⍵}¨(1+n⊃⎕LC)↓↓(180⌶)2⊃⎕XSI
      r←2↓∊(⎕UCS 13 10)∘,¨r
    ∇

    ∇ r←HtmlPage
      :Access public shared
      r←ScriptFollows
⍝<!DOCTYPE html>
⍝<html>
⍝<head>
⍝<meta content="text/html; charset=utf-8" http-equiv="Content-Type">
⍝<title>Jarvis</title>
⍝</head>
⍝<body>
⍝<fieldset>
⍝  <legend>Request</legend>
⍝  <form id="myform">
⍝    <table>
⍝      <tr>
⍝        <td><label for="function">Method to Execute:</label></td>
⍝        <td><input id="function" name="function" type="text"></td>
⍝      </tr>
⍝      <tr>
⍝        <td><label for="payload">JSON Data:</label></td>
⍝        <td><textarea id="payload" cols="100" name="payload" rows="10"></textarea></td>
⍝      </tr>
⍝      <tr>
⍝        <td colspan="2"><button onclick="doit()" type="button">Send</button></td>
⍝      </tr>
⍝    </table>
⍝  </form>
⍝</fieldset>
⍝<fieldset>
⍝  <legend>Response</legend>
⍝  <div id="result">
⍝  </div>
⍝</fieldset>
⍝<script>
⍝function doit() {
⍝  document.getElementById("result").innerHTML = "";
⍝  var xhttp = new XMLHttpRequest();
⍝  var fn = document.getElementById("function").value;
⍝  fn = (0 == fn.indexOf('/')) ? fn : '/' + fn;
⍝
⍝  xhttp.open("POST", fn, true);
⍝  xhttp.setRequestHeader("Content-Type", "application/json; charset=utf-8");
⍝
⍝  xhttp.onreadystatechange = function() {
⍝    if (this.readyState == 4){
⍝      if (this.status == 200) {
⍝        var resp = "<pre><code>" + this.responseText + "</code></pre>";
⍝      } else {
⍝        var resp = "<span style='color:red;'>" + this.statusText + "</span>";
⍝      }
⍝      document.getElementById("result").innerHTML = resp;
⍝    }
⍝  }
⍝  xhttp.send(document.getElementById("payload").value);
⍝}
⍝</script>
⍝</body>
⍝</html>
    ∇
    :EndSection

:EndClass
