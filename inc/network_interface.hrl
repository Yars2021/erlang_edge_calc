-export([form_header/1,
         form_task_body/1,
         form_response_body/1,
         form_report_body/1,
         form_message/2,
         form_message/3]).

%%%---------------------------------------------------------------------------------------------
%%%  Поля сообщений
%%%---------------------------------------------------------------------------------------------

% Класс сообщения
-type msg_class() :: sync | control | normal.

% Тип сообщения для линии супервизор-планировщик
-type sync_msg_code() :: recruit | expel | lock | unlock.

% Тип нормального сообщения
-type normal_msg_code() :: task | result | report.

% Тип сообщения для линии узел-супервизор
-type control_msg_code() :: join | leave.

% Код исполнения задачи
-type exitcode() :: ok | fail | timeout. 

% Статус узла
-type node_status() :: free | busy.

% Задача
-type task() :: {function(), list()}.

% Строка отчета узла
-type report_entry() :: {string(), atom() | number() | string() | boolean()}.

% Отчет узла
-type report() :: list(report_entry()).

-export_type([msg_class/0,
              sync_msg_code/0,
              normal_msg_code/0,
              control_msg_code/0,
              exitcode/0,
              node_status/0,
              task/0,
              report_entry/0,
              report/0]).


%%%---------------------------------------------------------------------------------------------
%%%  Тело сообщения
%%%---------------------------------------------------------------------------------------------

% Тело сообщения-задачи
-type task_msg_body() :: {integer(), task()}.

% Тело сообщения-ответа
-type response_msg_body() :: {exitcode(), string(), any()}.

% Тело сообщения-отчёта
-type report_msg_body() :: {node_status(), report()}.

-type msg_body() :: task_msg_body | response_msg_body | report_msg_body.

-export_type([task_msg_body/0,
              response_msg_body/0,
              report_msg_body/0,
              msg_body/0]).


%%%---------------------------------------------------------------------------------------------
%%%  Сообщение
%%%---------------------------------------------------------------------------------------------

% Заголовок сообщения
-type msg_header() :: {normal_msg_code(), integer(), any(), any(), any()}.

% Сообщение линии супервизор-планировщик
-type sync_message() :: {sync_msg_code(), any()}.

% Сообщение линии узел-супервизор
-type control_message() :: {control_msg_code(), any()}.

-type message() :: sync_message() | control_message() | {msg_header(), msg_body()}.

-export_type([msg_header/0,
              sync_message/0,
              control_message/0,
              message/0]).


%%%---------------------------------------------------------------------------------------------
%%%  Записи для формирования сообщений
%%%---------------------------------------------------------------------------------------------

-record(header, {code :: normal_msg_code(),
                 task_id :: integer(),
                 node_id :: any(),
                 supervisor :: any(),
                 scheduler :: any()}).

-record(task_body, {timeout :: integer(), task :: task()}).
-record(response_body, {exitcode :: exitcode(), comment :: string(), result :: any()}).
-record(report_body, {status :: node_status(), report :: report()}).

-record(sync_msg, {code :: sync_msg_code(), node :: any()}).
-record(control_msg, {code :: control_msg_code(), node :: any()}).


%%%---------------------------------------------------------------------------------------------
%%%  Функции для формирования сообщений
%%%---------------------------------------------------------------------------------------------

% Формирование заголовка сообщения из записи

form_header(#header{code=Code, task_id=TaskID, node_id=Node, supervisor=Supervisor, scheduler=Scheduler}) ->
    {Code, TaskID, Node, Supervisor, Scheduler}.


% Формирование тел сообщений из записей

form_task_body(#task_body{timeout=Timeout, task=Task}) ->
    {Timeout, Task}.

form_response_body(#response_body{exitcode=Exitcode, comment=Comment, result=Result}) ->
    {Exitcode, Comment, Result}.

form_report_body(#report_body{status=Status, report=Report}) ->
    {Status, Report}.


% Формирование сообщений разных классов
% sync - сообщения, корторыми обмениваются супервизор и планировщик
% control - сообщения, которыми узлы обмениваются с супервизором
% normal - сообщения, которыми планировщик обменивается с узлами

form_message(sync,
    #sync_msg{
        code=Code, 
        node=Node
    }) -> {Code, Node};

form_message(control,
    #control_msg{
        code=Code, 
        node=Node
    }) -> {Code, Node}.

form_message(normal,
    #header{
        code=task,
        task_id=TaskID,
        node_id=Node,
        supervisor=Supervisor,
        scheduler=Scheduler
    },
    #task_body{
        timeout=Timeout,
        task=Task
    }) ->
        {{task, TaskID, Node, Supervisor, Scheduler}, {Timeout, Task}};

form_message(normal,
    #header{
        code=result,
        task_id=TaskID,
        node_id=Node,
        supervisor=Supervisor,
        scheduler=Scheduler
    },
    #response_body{
        exitcode=Exitcode,
        comment=Comment,
        result=Result
    }) ->
        {{result, TaskID, Node, Supervisor, Scheduler}, {Exitcode, Comment, Result}};

form_message(normal,
    #header{
        code=report,
        task_id=TaskID,
        node_id=Node,
        supervisor=Supervisor,
        scheduler=Scheduler
    },
    #report_body{
        status=Status,
        report=Report
    }) ->
        {{report, TaskID, Node, Supervisor, Scheduler}, {Status, Report}}.
