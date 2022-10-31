export default {
    emits: [
        'connect'
    ],

    template: `
    <v-container fluid>
        <v-card elevation="2" class="mx-auto my-12" max-width="50%">
            <v-card-title>Visualization on Azure Batch</v-card-title>
            <v-card-subtitle>
                This application demonstrates how Azure Batch can be used to
                set an environment for interactive visualization.
            </v-card-subtitle>
            <v-card-text>
                <v-btn block @click='$emit("connect")'>Fetch Datasets</v-btn>
            </v-card-text>
        </v-card>
    </v-container>
    `
}