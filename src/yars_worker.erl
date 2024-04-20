-module(yars_worker).

-export([start/0,
         join/1,
         leave/1]).

-include("../inc/network_interface.hrl").


% Запуск исполнителя
start() ->
    register(yars_worker, spawn(fun() -> listen() end)).


% Регистрация у супервизора
join(Supervisor) ->
    Supervisor !
        form_message(
            control,
            #control_msg{
                code=join, 
                node={yars_worker, node()}
            }
        ).


% Снятие с регистрации у супервизора
leave(Supervisor) ->
    Supervisor !
        form_message(
            control,
            #control_msg{
                code=leave,
                node={yars_worker, node()}
            }
        ).


% Исполнить задачу с таймаутом
execute_task(Timeout, {Func, Args}) ->
    Self = self(),

    _Routine =
        spawn(
            fun() ->
                try Self ! {self(), Func(Args), ok}
                catch error:Error ->
                    Self ! {self(), Error, fail} 
                end
            end),

    receive
        {_, Result, ok} ->
            #response_body{
                exitcode=ok,
                comment="Execution successful",
                result=Result 
            };
        {_, Error, fail} ->
            #response_body{
                exitcode=fail,
                comment=Error,
                result=0 
            }
    after
        Timeout ->
            #response_body{
                exitcode=timeout,
                comment="Execution timed out",
                result=Timeout    
            }
    end.


% Обработка входящих сообщений
listen() ->
    receive
        {{task, TaskID, Node, Supervisor, Scheduler}, {Timeout, Task}} ->
            io:fwrite("Received task \"~p\". Executing.~n", [TaskID]),

            RepHeader = #header{
                code=report,
                task_id=TaskID,
                node_id=Node,
                supervisor=Supervisor,
                scheduler=Scheduler
            },

            Supervisor !
                form_message(
                    normal,
                    RepHeader,
                    #report_body{
                        status=busy,
                        report=[]
                    }
                ),

            Scheduler !
                form_message(
                    normal, 
                    #header{
                        code=result,
                        task_id=TaskID,
                        node_id=Node,
                        supervisor=Supervisor,
                        scheduler=Scheduler
                    }, 
                    execute_task(Timeout, Task)
                ),

            Supervisor !
                form_message(
                    normal,
                    RepHeader,
                    #report_body{
                        status=free,
                        report=[]
                    }
                );
        _ ->
            io:fwrite("Ignoring the invalid message.~n")
    end,

    listen().
