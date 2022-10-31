export default {
    props: {
      text: String,
      cancelable: Boolean,
    },

    data: () => ({
        show: true,
    }),

    emits: [
      'cancel'
    ],

    methods: {
      abort () {
        console.log('abort')
        this.$emit('cancel')
      },
    },

    template: `
    <v-container fluid class=fill-height>
    <v-dialog center hide-overlay persistent width="300" v-model='show'>
      <v-card light class="pt-2">
       <v-card-subtitle>
        {{text}}
        <v-icon v-if="cancelable" small @click="abort">mdi-close</v-icon>
       </v-card-subtitle>
        <v-card-text>
          <v-progress-linear indeterminate color="black" class="mb-0" ></v-progress-linear>
        </v-card-text>
      </v-card>
    </v-dialog>
    </v-container>
    `
}