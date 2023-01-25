import grid from "./grid.js"
import progressPopup from "./progressPopup.js"

export default {
    components: {
        grid,
        progressPopup,
    },

    emits: [
        'visualize',
        'failed'
    ],

    data:() => ({
        progress: {
            text: '',
            show: true,
        },
        columns: [{text: 'Filename', value: 'name', align: 'start'}, {text: 'Container Name', value: 'container'}],
        data: [],
        selected: [],
        actions_disabled: true,
        use_cropping: false,
        link_interactions: false,
    }),

    created() {
        this.refresh()
    },

    mounted() {
    },

    methods: {
        on_visualize() {
            this.$emit('visualize', this.selected, {
                'use_cropping': this.use_cropping,
                'link_interactions': this.link_interactions,
            })
        },

        refresh() {
            this.progress.text = 'refreshing data'
            this.progress.show = true
            this.fetch_data();
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
                this.on_error(error)
            })
        },

        on_error(msg) {
            console.log('failed:', msg)
            this.$emit('failed', msg)
        },

        on_selection_changed(items) {
            this.selected = []
            for (let i = 0; i < items.length; i++) {
                this.selected.push({'name': items[i].name, 'container': items[i].container})
            }
            this.actions_disabled = this.selected.length == 0;
        }
    },

    template: `
    <span>
        <progress-popup v-if="progress.show" :cancelable=false :text="progress.text"></progress-popup>
        <v-container v-else fluid>
            <v-card elevation="2" class="mx-auto my-12" max-width="75%">
                <v-card-title>Datasets in Storage Account</v-card-title>
                <v-card-text>
                    <grid :columns="columns" :data="data" @selection_changed="on_selection_changed"></grid>
                </v-card-text>
                <v-card-actions class="px-2">
                    <v-tooltip right>
                        <template v-slot:activator="{ on }">
                            <v-btn icon @click="refresh" v-on="on">
                                <v-icon>mdi-refresh</v-icon>
                            </v-btn>
                        </template>
                        <span>Reload datasets</span>
                    </v-tooltip>
                    <v-spacer></v-spacer>
                    <v-tooltip left>
                        <template v-slot:activator="{ on }">
                            <span v-on="on">
                                <v-checkbox v-model="use_cropping" :disabled="actions_disabled" on-icon="mdi-crop" off-icon="mdi-crop"></v-checkbox>
                            </span>
                        </template>
                        <span>Use cropping view (if possible)</span>
                    </v-tooltip>
                    <v-tooltip left>
                        <template v-slot:activator="{ on, attrs }">
                            <span v-on="on">
                                <v-checkbox v-model="link_interactions" :disabled="actions_disabled" on-icon="mdi-link" off-icon="mdi-link-off"></v-checkbox>
                            </span>
                        </template>
                        <span>Link interactions between supported views</span>
                    </v-tooltip>
                    <v-btn :disabled="actions_disabled" @click="on_visualize">
                        <v-icon>mdi-microsoft-azure</v-icon>
                        Visualize
                    </v-btn>
                </v-card-actions>
            </v-card>
        </v-container>
    </span>
    `
}