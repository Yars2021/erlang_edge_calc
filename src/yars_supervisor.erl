-module(yars_supervisor).

-export([start/1]).

-include("../inc/network_interface.hrl").


% Запуск супервизора
start(Scheduler) ->
    register(yars_supervisor, spawn(fun() -> listen(Scheduler, []) end)).


% Оповещение планировщика
send_to_scheduler(Code, Node, Scheduler) ->
    Scheduler !
        form_message(
            sync,
            #sync_msg{
                code=Code,
                node=Node
            }
        ).


% Добавить узел в кластер
append_node(Node, []) -> [{free, Node}];
append_node(Node, [{Status, Node} | Tail]) -> [{Status, Node} | Tail];
append_node(Node, [Head | Tail]) -> [Head | append_node(Node, Tail)].


% Удаление узла из списка
remove_node(_, []) -> [];
remove_node(Node, [{_, Node} | Tail]) -> Tail;
remove_node(Node, [Head | Tail]) -> [Head | remove_node(Node, Tail)].


% Изменене статуса узла
set_status(_, _, []) -> [];
set_status(Status, Node, [{_, Node} | Tail]) -> [{Status, Node} | Tail];
set_status(Status, Node, [Head | Tail]) -> [Head | set_status(Status, Node, Tail)].


% Обработка входящих сообщений
listen(Scheduler, Cluster) ->
    receive
        {join, Node} ->
            io:fwrite("Node trying to join.~n"),
            send_to_scheduler(recruit, Node, Scheduler),
            listen(Scheduler, append_node(Node, Cluster));

        {leave, Node} ->
            io:fwrite("Node trying to leave.~n"),
            send_to_scheduler(expel, Node, Scheduler),
            listen(Scheduler, remove_node(Node, Cluster));

        {{report, _, Node, _, Scheduler}, {busy, _}} ->
            send_to_scheduler(lock, Node, Scheduler),
            listen(Scheduler, set_status(busy, Node, Cluster));

        {{report, _, Node, _, Scheduler}, {free, _}} ->
            send_to_scheduler(unlock, Node, Scheduler),
            listen(Scheduler, set_status(free, Node, Cluster));

        _ ->
            io:fwrite("Ignoring the invalid message.~n")
    end,

    listen(Scheduler, Cluster).
