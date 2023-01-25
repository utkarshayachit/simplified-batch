import progressPopup from "./progressPopup.js"
export default {
    components: {
        progressPopup,
    },

    props: {
        datasets: Array(),
        options: Object(),
    },

    emits: [
        'failed',
        'done',
    ],

    data: () => ({
        progress: {
            show: false,
            text: '',
            cancelable: true,
        },
        url: '',
        job: null,

    }),

    created() {
        this.abortController = new AbortController();
        this.start();
    },

    methods: {
        async start() {
            console.log('start job');
            await this.shutdown()
            try {
                // submit job request
                this.progress.show = true
                this.progress.cancelable = true
                this.progress.text = 'submitting visualization job'
                let reply = await fetch('/job', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json;charset=utf-8'
                    },
                    body: JSON.stringify({
                        datasets: this.datasets,
                        options: this.options,
                    }),
                    signal: this.abortController.signal,
                })
                .then((response) => response.json());
                if (!reply.success) { throw Error(reply.message); }
                this.job = reply.job;

                // fetch redirect url for job, this will wait
                // for the job to start or timeout.
                this.progress.text = 'awaiting job to start executing'
                reply = await fetch('/compute_node', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json;charset=utf-8'
                    },
                    body: JSON.stringify({ job: this.job }),
                    signal: this.abortController.signal,
                })
                .then((response) => response.json());
                if (!reply.success) { throw Error(reply.message); }
                this.progress.text = 'connecting to visualization backend'
                this.progress.cancelable = false
                this.url = `${window.location.origin}/${reply.path}`
                this.progress.show = false
            } catch (error) {
                if (error.name != 'AbortError') {
                   this.on_error(error);
                }
            }
        },

        async on_error(msg) {
            // terminate job if it has been scheduled/started.
            await this.shutdown();
            console.log('failed:', msg);
            this.$emit('failed', msg);
        },

        async close() {
            // shutdown job, if submitted.
            this.progress.text = 'cancelling job'
            this.progress.cancelable = false
            await this.shutdown();
            this.$emit('done')
        },

        async shutdown() {
            this.abortController.abort();
            this.abortController = new AbortController();

            if (!this.job) { return; }
            let job = this.job
            this.job = null
            let reply = await fetch('/terminate_job', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json;charset=utf-8'
                },
                body: JSON.stringify({ job: job })
            })
            .then((response) => {
                if (!response.ok) { throw Error(response.body)}
                return response
            })
            .then((response) => response.json())
            .catch((error)=>{
                this.on_error(error)
            })
        },
    },

    template: `
    <span>
        <progress-popup v-if="progress.show" :text="progress.text" :cancelable="progress.cancelable" @cancel="close">
        </progress-popup>
        <v-container v-else fluid class="fill-height">
        <v-card elevation="2" class="mx-auto my-12" width="90%" height="90%" style="position: relative">
            <v-system-bar dark>
                    <v-spacer></v-spacer>
                    <v-icon @click='close'>mdi-close-box</v-icon>
            </v-system-bar>

            <v-card-text class="fill-height pa-0">
                    <iframe :src="url" width="100%" height="100%"></iframe>
            </v-card-text>
            </v-card>
        </v-container>
    </span>
    `
}