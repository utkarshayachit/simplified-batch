import argparse

from . import utils


def add_arguments(parser: argparse.ArgumentParser) -> None:
    g = parser.add_mutually_exclusive_group(required=True)
    g.add_argument('-r','--resize-pool', type=int, help='resize pool',metavar='SIZE')
    g.add_argument('-j','--submit-job', action='store_true')

    sg = parser.add_argument_group('submit-job', 'arguments for job submission')
    sg.add_argument('-s','--start-trade', type=int, help='start trade number', default=0)
    sg.add_argument('-w','--trade-window', type=int, help='trade window i.e. total number of trades', default=0)
    sg.add_argument('-t','--tasks', type=int, help='total number of tasks', default=1)
    sg.add_argument('-i','--container-image',type=str, help='container image name', default='')
    sg.add_argument('-a','--algorithm', choices=['deltavega', 'pvonly', 'synthetic'], default='deltavega', help='pricing algorithm')
    sg.add_argument("--failure", type=float, default=0.0, help="inject random task failure with this probability (default: 0.0)")

    tg = parser.add_argument_group('synthetic', 'arguments with algorithm=\'synthetic\'')
    tg.add_argument("-d", "--delay-start", type=int, default=0, help="delay startup time in seconds (default: 0)")
    tg.add_argument("-m", "--mem-usage", type=int, default=16, help="memory usage for task in MB (default: 16)")
    tg.add_argument("--task-duration", type=int, default=20, help="task duration in milliseconds (default: 20)")


command = '/bin/sh -c "python3 -m azfinsim --start-trade {start} --trade-window {delta} --failure {failure} --algorithm {algorithm} ' \
          '--delay-start {delay_start} --mem-usage {mem_usage} --task-duration {task_duration} --arguments $AZ_BATCH_JOB_PREP_WORKING_DIR/azfinsim.$AZ_BATCH_JOB_ID.args"'

def task_commandline_generator(args):
    delta = args.trade_window // args.tasks
    assert delta >= 0

    counter = 0
    for start in range(args.start_trade, args.start_trade + args.trade_window,  delta):
        yield command.format(start=start, delta=delta, algorithm=args.algorithm,
            failure=args.failure, delay_start=args.delay_start, mem_usage=args.mem_usage, task_duration=args.task_duration)
        counter += 1

def execute(args)->None:
    if args.resize_pool is not None:
        utils.pool_resize(endpoint=args.batch_endpoint, pool_id='azfinsim-pool', targetSize=args.resize_pool)
    else:
        # utils.submit_job(endpoint=args.batch_endpoint, pool_id='azfinsim-pool',
        #     num_tasks=args.tasks, tasks=task_generator(args),
        #     task_container_image=args.container_image,
        # )
        tasks =[ i for i in task_commandline_generator(args)]
        print(tasks)
        