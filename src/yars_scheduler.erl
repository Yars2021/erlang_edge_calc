-module(yars_scheduler).

-export([start/1,
         generate_id/0]).

-include("../inc/network_interface.hrl").


% Запуск планировщика
start(Supervisor) ->
    register(yars_scheduler, spawn(fun() -> listen(Supervisor, {yars_scheduler, node()}, []) end)),
    register(yars_agregator, spawn(fun() -> agregate([], []) end)).


% Сгенерировать уникальный ID
generate_id() ->
    rand:uniform(1_000_000_000_000).


% Печать кластера
print_cluster([]) -> io:fwrite("~n");
print_cluster([Head | Tail]) ->
    io:fwrite("~p~n", [Head]),
    print_cluster(Tail).


% Удаление узла из списка
remove_node(_, []) -> [];
remove_node(Node, [{_, Node, _} | Tail]) -> Tail;
remove_node(Node, [Head | Tail]) -> [Head | remove_node(Node, Tail)].


% Изменене статуса узла
set_status(_, _, []) -> [];
set_status(Status, Node, [{_, Node, Queue} | Tail]) -> [{Status, Node, Queue} | Tail];
set_status(Status, Node, [Head | Tail]) -> [Head | set_status(Status, Node, Tail)].


% Найти запись с первым свободным узлом в кластере
find_first_free([]) -> {empty_cluster};
find_first_free([{busy, _, _}]) -> {all_busy};
find_first_free([{free, Node, Queue} | _]) -> {free, Node, Queue};
find_first_free([_ | Tail]) -> find_first_free(Tail).


% Компаратор для приоритетов
comp({_, _, _, APr, _}, {_, _, _, BPr, _}) -> APr > BPr.


% Найти занятость узла
get_load({_, _, []}) -> 0;
get_load({Status, Node, [{_, _, _, _, Timeout} | Tail]}) ->
    Timeout + get_load({Status, Node, Tail}).


% Найти узел с минимальной очередью
get_least_busy([]) -> {empty_cluster};
get_least_busy([Head | Tail]) -> get_least_busy(Tail, Head).

get_least_busy([], RetVal) -> RetVal;

get_least_busy([Head | Tail], RetVal) ->
    Load1 = get_load(Head),
    Load2 = get_load(RetVal),

    case Load1 > Load2 of
        true -> get_least_busy(Tail, RetVal);
        false -> get_least_busy(Tail, Head)
    end.


% Добавить задачу в очередь наименее занятому из узлов
cluster_queue_task(_, _, []) -> [];
cluster_queue_task(Run, Task, Cluster) -> queue_task(Run, Task, get_least_busy(Cluster), Cluster).


% Добавить задачу в очередь узла с учетом приоритета
queue_task(_, _, _, []) -> {empty_cluster};

queue_task(Run, Task, {Status, Node, Queue}, [{Status, Node, Queue} | Tail]) ->
    {yars_agregator, node()} ! {exec, Run, Node, Task},
    [{Status, Node, lists:sort(fun comp/2, [Task | Queue])} | Tail];

queue_task(Run, Task, Node, [Head | Tail]) ->
    [Head | queue_task(Run, Task, Node, Tail)].


% Начать исполнение первой задачи из очереди узла
execute(_, _, {Status, Node, []}) -> {Status, Node, []};

execute(_, _, {busy, Node, Queue}) -> {busy, Node, Queue};

execute(Supervisor, Scheduler, {free, Node, [{TaskID, Func, Args, Priority, Timeout} | Tail]}) ->
    {yars_agregator, node()} !
        {exec, 1, {TaskID, Func, Args, Priority, Timeout}},

    Node !
        form_message(
            normal,
            #header{
                code=task,
                task_id=TaskID,
                node_id=Node,
                supervisor=Supervisor,
                scheduler=Scheduler
            },
            #task_body{
                timeout=Timeout,
                task={Func, Args}
            }
        ),

    {free, Node, Tail}.


% Начать исполнение всех возможных задач
execute_all(_, _, []) -> [];

execute_all(Supervisor, Scheduler, [Head | Tail]) ->
    [execute(Supervisor, Scheduler, Head) | execute_all(Supervisor, Scheduler, Tail)].


% Отметить задачу как решенную
mark_as_done(TaskID, Result) -> {yars_agregator, node()} ! {ok, TaskID, Result}.


% Отметить задачу как завершенную с ошибкой
mark_as_failed(TaskID) -> {yars_agregator, node()} ! {fail, TaskID}.


% Сообщить агрегатору о повторном исполнении задачи
retry_task(TaskID) -> {yars_agregator, node()} ! {retry, TaskID}.


% Обработка входящих сообщений от узлов и супервизора
listen(Supervisor, Scheduler, Cluster) ->
    receive
        {view} ->
            io:fwrite("Current cluster:~n~n"),
            print_cluster(Cluster),
            io:fwrite("~n");

        {exec, Run, Func, Args, Priority, Timeout} ->
            NodeRecord = find_first_free(Cluster),

            case NodeRecord of
                {empty_cluster} ->
                    io:fwrite("Cluster is empty, unable to allocate.~n");

                {all_busy} ->
                    listen(
                        Supervisor,
                        Scheduler,
                        cluster_queue_task(
                            Run,
                            {generate_id(), Func, Args, Priority, Timeout},
                            Cluster
                        )
                    );

                NodeRecord ->
                    listen(
                        Supervisor,
                        Scheduler,
                        queue_task(
                            Run,
                            {generate_id(), Func, Args, Priority, Timeout},
                            NodeRecord,
                            Cluster
                        )
                    )
            end;

        {recruit, Node} ->
            listen(Supervisor, Scheduler, [{free, Node, []} | Cluster]);

        {expel, Node} ->
            listen(Supervisor, Scheduler, remove_node(Node, Cluster));

        {lock, Node} ->
            listen(Supervisor, Scheduler, set_status(busy, Node, Cluster));

        {unlock, Node} ->
            listen(Supervisor, Scheduler, set_status(free, Node, Cluster));

        {{result, TaskID, _, _, Scheduler}, {ok, Comment, Result}} ->
            io:fwrite("Task \"~p\" executed successfully.~nComment: ~p.~n", [TaskID, Comment]),
            mark_as_done(TaskID, Result);

        {{result, TaskID, _, _, _}, {fail, Comment, _}} ->
            io:fwrite("Task \"~p\" failed.~nComment: ~p.~n", [TaskID, Comment]),
            mark_as_failed(TaskID);

        {{result, TaskID, _, _, _}, {timeout, Comment, _}} ->
            io:fwrite("Task ~p: ~p.~n", [TaskID, Comment]),
            retry_task(TaskID);

        _ ->
            io:fwrite("Ignoring the invalid message.~n")
    end,

    listen(Supervisor, Scheduler, execute_all(Supervisor, Scheduler, Cluster)).


% Найти задачу по ID
get_task(_, []) -> {task_not_found};
get_task(TaskID, [{_, TaskID, Func, Args, _, _} | _]) -> {Func, Args};
get_task(TaskID, [_ | Tail]) -> get_task(TaskID, Tail).


% Убрать задачу по ID
remove_task(_, []) -> [];
remove_task(TaskID, [{_, TaskID, _, _, _, _} | Tail]) -> Tail;
remove_task(TaskID, [_ | Tail]) -> remove_task(TaskID, Tail).


% Найти полную запись о задаче
get_full_task(_, []) -> {task_not_found};

get_full_task(TaskID, [{Run, TaskID, Func, Args, Priority, Timeout} | _]) ->
    {Run, TaskID, Func, Args, Priority, Timeout};

get_full_task(TaskID, [_ | Tail]) -> get_full_task(TaskID, Tail).


% Хранение результатов исполнения и информации о задачах
agregate(Tasks, Results) ->
    receive
        {fail, TaskID} ->
            agregate(remove_task(TaskID, Tasks), Results);

        {ok, TaskID, Result} ->
            Task = get_task(TaskID, Tasks),
            agregate(remove_task(TaskID, Tasks), [{Task, Result} | Results]);

        {exec, Run, {TaskID, Func, Args, Priority, Timeout}} ->
            agregate([{Run, TaskID, Func, Args, Priority, Timeout} | Tasks], Results);

        {retry, TaskID} ->
            {Run, TaskID, Func, Args, Priority, Timeout} = get_full_task(TaskID, TaskID),

            case Run >= 3 of
                true -> agregate(remove_task(TaskID, Tasks), Results);
                false ->
                    {yars_scheduler, node()} !
                        {exec, Run + 1, Func, Args, Priority, (Timeout + 1) * 2},
                    agregate(remove_task(TaskID, Tasks), Results)
            end
    end,

    agregate(Tasks, Results).
