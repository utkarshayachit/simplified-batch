import grid from "./grid.js"
import progressPopup from "./progressPopup.js"

export default {
    components: {
        grid,
        progressPopup,
    },

    emits: [
        'clicked',
        'failed'
    ],

    data:() => ({
        progress: {
            text: '',
            show: true,
        },
        columns: [{text: 'Filename', value: 'name'}, {text: 'Container Name', value: 'container'}, 
                  {text: '', value:'actions', sortable: false}],
        data: [],
    }),

    created() {
        this.progress.text = 'accessing storage account'
        this.progress.show = true
        this.fetch_data();
    },

    mounted() {
    },

    methods: {
        on_select(datasetName, containerName) {
            console.log('selected dataset', datasetName, containerName);
            this.$emit('clicked', datasetName, containerName);
        },

        async fetch_data() {
            this.data = [];
            fetch('/datasets')
            .then((response) => response.json())
            .then((reply) => {
                if (reply.success) {
                    this.data = reply.data;
                    this.progress.show = false
                } else {
                    throw Error(reply.message);
                }
            })
            .catch((error) => {
                this.on_error(error);
            })
        },

        on_error(msg) {
            console.log('failed:', msg);
            this.$emit('failed', msg);
        }
    },

    template: `
    <span>
        <progress-popup v-if="progress.show" :cancelable=false :text="progress.text"></progress-popup>
        <v-container v-else fluid>
            <v-card elevation="2" class="mx-auto my-12" max-width="75%">
                <v-card-title>Datasets in Storage Account</v-card-title>
                <v-card-text>
                    <grid :columns="columns" :data="data" @view="on_select"></grid>
                </v-card-text>
            </v-card>
        </v-container>
    </span>
    `
}